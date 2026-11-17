with Ada.Directories;         use Ada.Directories;
with Ada.Characters.Handling; use Ada.Characters.Handling;
with Engine.Units;            use Engine.Units;
with Engine.Game;             use Engine.Game;
with Engine.Text_Util;        use Engine.Text_Util;

package body Engine.Campaign is

   use Ada.Text_IO;

   procedure Load_Campaign (Path : String) is
      F : File_Type;
   begin
      C := (others => <>);
      C.Path := To_Unbounded_String (Path);
      Open (F, In_File, Path);
      while not End_Of_File (F) loop
         declare
            Line : constant String := Get_Line (F);
            KW   : constant String := Keyword (Line);
         begin
            if KW = "title" then
               C.Title := To_Unbounded_String (Rest (Line));
            elsif KW = "description" then
               if Length (C.Description) > 0 then
                  Append (C.Description, " ");
               end if;
               Append (C.Description, Rest (Line));
            elsif KW = "player" then
               C.Player := Player_Side (Integer'Value (Rest (Line)));
            elsif KW = "prestige" then
               C.Prestige := Integer'Value (Rest (Line));
            elsif KW = "stage" then
               C.Stages.Append
                 ((Id      => To_Unbounded_String (Value (Line, "id")),
                   File    => To_Unbounded_String (Value (Line, "file")),
                   On_Win  => To_Unbounded_String
                     (Value (Line, "win", "victory")),
                   On_Loss => To_Unbounded_String
                     (Value (Line, "loss", "defeat"))));
            end if;
         end;
      end loop;
      Close (F);
      if C.Stages.Is_Empty then
         raise Campaign_Error with Path & ": no stages";
      end if;
      C.Current := 1;
      C.Active  := True;
   exception
      when Ada.Text_IO.Name_Error | Ada.Text_IO.Use_Error =>
         raise Campaign_Error with "cannot open " & Path;
   end Load_Campaign;

   procedure Stop is
   begin
      C.Active := False;
   end Stop;

   ---------------
   -- Carryover --
   ---------------

   procedure Apply_Carryover is
      P    : constant Player_Side := C.Player;
      Used : array (1 .. Natural (G.Units.Length)) of Boolean :=
        (others => False);
   begin
      for K of C.Carried loop
         declare
            T : constant Natural := Find_Type (To_String (K.Type_Id));
            Placed : Boolean := False;
         begin
            if T /= 0 then
               --  Fill a matching core slot of the scenario.
               for I in Used'Range loop
                  declare
                     U : Unit renames G.Units (I);
                  begin
                     if not Used (I) and then U.Alive and then U.Side = P
                       and then U.Core
                       and then Is_Air (G.Types (U.Kind))
                                = Is_Air (G.Types (T))
                     then
                        Used (I)     := True;
                        U.Kind       := T;
                        U.Experience := K.Experience;
                        U.Strength   := Max_Strength;
                        Placed       := True;
                        exit;
                     end if;
                  end;
               end loop;
               --  Extra units (bought last time) go to a deployment hex.
               if not Placed then
                  Outer :
                  for Col in 0 .. G.Cols - 1 loop
                     for Row in 0 .. G.Rows - 1 loop
                        if Can_Deploy (T, P, (Col, Row)) then
                           declare
                              N : Unit;
                           begin
                              N.Kind := T;
                              N.Side := P;
                              N.Pos  := (Col, Row);
                              N.Experience := K.Experience;
                              N.Core := True;
                              Add_Unit (N);
                           end;
                           exit Outer;
                        end if;
                     end loop;
                  end loop Outer;
               end if;
            end if;
         end;
      end loop;
      --  Core slots nobody survived to fill stay empty.
      for I in Used'Range loop
         if not Used (I) and then G.Units (I).Side = P
           and then G.Units (I).Core
         then
            Remove_Unit (I);
         end if;
      end loop;
   end Apply_Carryover;

   procedure Start_Stage is
      S : constant Stage := C.Stages (C.Current);
   begin
      Engine.Loader.Load_Scenario
        (Engine.Loader.Data_Dir & "/scenarios/" & To_String (S.File),
         Start => False);
      G.Sides (C.Player).Control := Human;
      G.Sides (Other (C.Player)).Control := Computer;
      if not C.Fresh then
         Apply_Carryover;
      end if;
      G.Sides (C.Player).Prestige := G.Sides (C.Player).Prestige + C.Prestige;
      Start_Game;
      Log ("Campaign " & To_String (C.Title) & ", battle"
           & Natural'Image (C.Current));
   end Start_Stage;

   function Find_Stage (Id : String) return Natural is
   begin
      for I in C.Stages.First_Index .. C.Stages.Last_Index loop
         if To_String (C.Stages (I).Id) = Id then
            return I;
         end if;
      end loop;
      return 0;
   end Find_Stage;

   function Finish_Stage (Report : out Unbounded_String) return Boolean is
      Won  : constant Boolean := G.Winner = C.Player;
      Next : constant String :=
        To_String (if Won then C.Stages (C.Current).On_Win
                   else C.Stages (C.Current).On_Loss);
      Survivors : Natural := 0;
   begin
      if Won then
         C.Won := C.Won + 1;
      else
         C.Lost := C.Lost + 1;
      end if;
      C.Carried.Clear;
      for U of G.Units loop
         if U.Alive and then U.Side = C.Player and then U.Core then
            C.Carried.Append ((G.Types (U.Kind).Id, U.Experience));
            Survivors := Survivors + 1;
         end if;
      end loop;
      C.Prestige := Integer'Max (0, G.Sides (C.Player).Prestige);
      C.Fresh := False;

      Report := To_Unbounded_String
        ((if Won then "Battle won!" else "Battle lost.")
         & ASCII.LF & Image (Survivors) & " core units survive and keep "
         & "their experience. Prestige carried: " & Image (C.Prestige));

      declare
         N : constant Natural := Find_Stage (Next);
      begin
         if N = 0 then
            C.Active := False;
            Append (Report, ASCII.LF & ASCII.LF
                    & (if Next = "victory"
                       then "CAMPAIGN COMPLETE - VICTORY!"
                       elsif Next = "defeat"
                       then "The campaign has ended in defeat."
                       else "The campaign is over.")
                    & ASCII.LF & "Battles won:" & Natural'Image (C.Won)
                    & ", lost:" & Natural'Image (C.Lost));
            return False;
         end if;
         C.Current := N;
         Append (Report, ASCII.LF & ASCII.LF & "Next battle: "
                 & To_String (C.Stages (N).File));
         return True;
      end;
   end Finish_Stage;

   -------------
   -- Upgrade --
   -------------

   function Current_Type (K : Positive) return Natural is
     (Find_Type (To_String (C.Carried (K).Type_Id)));

   function Can_Upgrade (K : Positive; T : Positive) return Boolean is
      From : constant Natural := Current_Type (K);
   begin
      if K > Natural (C.Carried.Length) or else From = 0
        or else T > Natural (G.Types.Length) or else T = From
      then
         return False;
      end if;
      declare
         A : constant Unit_Type := G.Types (From);
         B : constant Unit_Type := G.Types (T);
      begin
         return B.Buyable and then B.Class = A.Class
           and then Is_Air (B) = Is_Air (A)
           and then May_Buy (T, C.Player)
           and then Upgrade_Cost (K, T) <= C.Prestige;
      end;
   end Can_Upgrade;

   function Upgrade_Cost (K : Positive; T : Positive) return Natural is
      From : constant Natural := Current_Type (K);
   begin
      if From = 0 then
         return Natural'Last / 2;
      end if;
      --  Pay the difference, but re-equipping is never quite free.
      return Natural'Max (G.Types (T).Cost / 10,
                          G.Types (T).Cost
                          - Natural'Min (G.Types (T).Cost,
                                         G.Types (From).Cost));
   end Upgrade_Cost;

   procedure Upgrade (K : Positive; T : Positive) is
   begin
      if Can_Upgrade (K, T) then
         C.Prestige := C.Prestige - Upgrade_Cost (K, T);
         C.Carried (K).Type_Id := G.Types (T).Id;
      end if;
   end Upgrade;

   --------------------
   -- List_Campaigns --
   --------------------

   function List_Campaigns return Engine.Loader.Info_Vectors.Vector is
      Result : Engine.Loader.Info_Vectors.Vector;
      Dir    : constant String := Engine.Loader.Data_Dir & "/campaigns";
      Search : Search_Type;
      Item   : Directory_Entry_Type;
   begin
      if not Exists (Dir) then
         return Result;
      end if;
      Start_Search (Search, Dir, "*.cmp");
      while More_Entries (Search) loop
         Get_Next_Entry (Search, Item);
         declare
            Info : Engine.Loader.Scenario_Info;
            F    : File_Type;
         begin
            Info.Path  := To_Unbounded_String (Full_Name (Item));
            Info.Title := To_Unbounded_String (Simple_Name (Item));
            Open (F, In_File, Full_Name (Item));
            while not End_Of_File (F) loop
               declare
                  Line : constant String := Get_Line (F);
                  KW   : constant String := Keyword (Line);
               begin
                  if KW = "title" then
                     Info.Title := To_Unbounded_String (Rest (Line));
                  elsif KW = "era" then
                     Info.Era := To_Unbounded_String (To_Upper (Rest (Line)));
                  elsif KW = "description" then
                     if Length (Info.Description) > 0 then
                        Append (Info.Description, " ");
                     end if;
                     Append (Info.Description, Rest (Line));
                  elsif KW = "stage" and then Length (Info.Preview) = 0 then
                     --  Preview shows the first battle.
                     Info.Preview := To_Unbounded_String
                       (Engine.Loader.Data_Dir & "/scenarios/"
                        & Value (Line, "file"));
                  end if;
               end;
            end loop;
            Close (F);
            Result.Append (Info);
         end;
      end loop;
      End_Search (Search);
      return Result;
   end List_Campaigns;

   -----------------
   -- Persistence --
   -----------------

   procedure Write_State (F : File_Type) is
   begin
      if not C.Active then
         return;
      end if;
      Put_Line (F, "campaign_path " & To_String (C.Path));
      Put_Line (F, "campaign_state current=" & Image (C.Current)
                & " prestige=" & Image (C.Prestige)
                & " fresh=" & (if C.Fresh then "1" else "0")
                & " won=" & Image (C.Won) & " lost=" & Image (C.Lost));
      for K of C.Carried loop
         Put_Line (F, "carried type=" & To_String (K.Type_Id)
                   & " exp=" & Image (K.Experience));
      end loop;
   end Write_State;

   procedure Read_State_Line (Line : String) is
      KW : constant String := Keyword (Line);
   begin
      if KW = "campaign_path" then
         Load_Campaign (Rest (Line));
      elsif KW = "campaign_state" then
         C.Current  := Int (Line, "current", 1);
         C.Prestige := Int (Line, "prestige", 0);
         C.Fresh    := Int (Line, "fresh", 1) = 1;
         C.Won      := Int (Line, "won", 0);
         C.Lost     := Int (Line, "lost", 0);
      elsif KW = "carried" then
         C.Carried.Append
           ((To_Unbounded_String (Value (Line, "type")),
             Int (Line, "exp", 0)));
      end if;
   end Read_State_Line;

end Engine.Campaign;
