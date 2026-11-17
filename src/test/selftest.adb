--  Headless engine check: plays every scenario AI-vs-AI and reports,
--  then exercises save/load and a full campaign.
with Ada.Text_IO;            use Ada.Text_IO;
with Ada.Command_Line;       use Ada.Command_Line;
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with Engine;                 use Engine;
with Engine.Game;            use Engine.Game;
with Engine.Loader;          use Engine.Loader;
with Engine.AI;
with Engine.Save;
with Engine.Campaign;
with Engine.Editing;
with Engine.Terrain;

procedure Selftest is
   Verbose : constant Boolean :=
     Argument_Count > 0 and then Argument (1) = "-v";
   Rounds  : constant Positive :=
     (if Argument_Count > 0 and then Argument (1) /= "-v"
      then Positive'Value (Argument (1)) else 1);

   procedure Play_Turn is
   begin
      Engine.AI.Begin_Turn;
      while Engine.AI.Step loop
         null;
      end loop;
      End_Turn;
   end Play_Turn;

   procedure Play_Out is
   begin
      G.Sides (1).Control := Computer;
      G.Sides (2).Control := Computer;
      while G.Winner = 0 loop
         Play_Turn;
      end loop;
   end Play_Out;

   function Alive (S : Player_Side) return Natural is
      N : Natural := 0;
   begin
      for U of G.Units loop
         if U.Alive and then U.Side = S then
            N := N + 1;
         end if;
      end loop;
      return N;
   end Alive;

   Wins : array (1 .. 20, Player_Side) of Natural :=
     (others => (others => 0));
   List : constant Info_Vectors.Vector := List_Scenarios;
begin
   Record_Effects := False;
   for R in 1 .. Rounds loop
      for I in List.First_Index .. List.Last_Index loop
         Load_Scenario (To_String (List (I).Path));
         Play_Out;
         Wins (I, G.Winner) := Wins (I, G.Winner) + 1;
         if Verbose then
            for M of Messages loop
               Put_Line ("   " & M);
            end loop;
         end if;
         Messages.Clear;
         if Rounds = 1 then
            Put_Line (To_String (List (I).Title) & ": "
                      & To_String (G.Sides (G.Winner).Name)
                      & " wins on turn" & G.Turn'Image & ", objectives"
                      & Victory_Hexes_Owned (G.Attacker)'Image & " /"
                      & Victory_Hexes_Total'Image & ", units left"
                      & Alive (1)'Image & " vs" & Alive (2)'Image);
         end if;
      end loop;
   end loop;
   if Rounds > 1 then
      for I in List.First_Index .. List.Last_Index loop
         Put_Line (To_String (List (I).Title) & ": attacker won"
                   & Wins (I, 1)'Image & " of" & Rounds'Image);
      end loop;
   end if;

   --  Save / load round trip.
   declare
      Path : constant String := "/tmp/hexfront_selftest.sav";
      N1, N2 : Natural;
   begin
      Load_Scenario (To_String (List.First_Element.Path));
      G.Sides (1).Control := Computer;
      G.Sides (2).Control := Computer;
      for K in 1 .. 4 loop
         Play_Turn;
      end loop;
      N1 := Alive (1) + Alive (2);
      Engine.Save.Save_Game (Path);
      Engine.Save.Load_Game (Path);
      N2 := Alive (1) + Alive (2);
      Put_Line ("save/load: units" & N1'Image & " ->" & N2'Image
                & ", turn" & G.Turn'Image
                & (if N1 = N2 then "  OK" else "  MISMATCH"));
      Play_Out;
   end;

   --  Editor round trip: every scenario written back out must load again
   --  with the same number of units.
   for Info of List loop
      declare
         Path : constant String := "/tmp/hexfront_rt.scn";
         N1, N2 : Natural;
      begin
         Load_Scenario (To_String (Info.Path), Start => False);
         N1 := Alive (1) + Alive (2);
         Engine.Editing.Write_Scenario (Path);
         Load_Scenario (Path, Start => False);
         N2 := Alive (1) + Alive (2);
         if N1 /= N2 then
            Put_Line ("editor round trip MISMATCH: " & To_String (Info.Title));
         end if;
      end;
   end loop;
   Put_Line ("editor round trip: done");

   --  Build a scenario from scratch with the editor operations.
   declare
      use Engine.Editing;
      Path : constant String := "/tmp/hexfront_new.scn";
   begin
      New_Map ("napoleonic", 12, 8);
      for C in 0 .. 11 loop
         Paint ((C, 4), Engine.Terrain.Road);
      end loop;
      Paint ((9, 4), Engine.Terrain.Town);
      Set_Place ((9, 4), "Testburg", 2, True);
      Put_Unit ((1, 3), 1, Find_Type ("line"));
      Put_Unit ((1, 5), 1, Find_Type ("cuirass"));
      Put_Unit ((2, 4), 1, Find_Type ("footart"));
      Put_Unit ((9, 4), 2, Find_Type ("line"));
      Put_Unit ((9, 4), 2, Find_Type ("grenadier"));   --  replaces line
      Put_Line ("editor validate: '" & Validate & "'");
      Write_Scenario (Path);
      Load_Scenario (Path);
      Put_Line ("editor scenario: " & To_String (G.Title) & ", units"
                & Natural'Image (Alive (1) + Alive (2)));
      Play_Out;
      Put_Line ("editor scenario played: winner "
                & To_String (G.Sides (G.Winner).Name));
   end;

   --  Campaign run.
   declare
      Report : Unbounded_String;
      Camps  : constant Info_Vectors.Vector :=
        Engine.Campaign.List_Campaigns;
   begin
      for Cp of Camps loop
         Put_Line ("campaign: " & To_String (Cp.Title));
         Engine.Campaign.Load_Campaign (To_String (Cp.Path));
         loop
            Engine.Campaign.Start_Stage;
            Put_Line ("  stage " & To_String (G.Title) & ": side 1 has"
                      & Alive (1)'Image & " units, prestige"
                      & G.Sides (1).Prestige'Image);
            Play_Out;
            exit when not Engine.Campaign.Finish_Stage (Report);
            --  Spend prestige on the first possible upgrades.
            declare
               use Engine.Campaign;
               Done : Natural := 0;
            begin
               for K in 1 .. Natural (C.Carried.Length) loop
                  for T in G.Types.First_Index .. G.Types.Last_Index loop
                     if Can_Upgrade (K, T)
                       and then G.Types (T).Cost
                         > G.Types (Find_Type
                                      (To_String (C.Carried (K).Type_Id))).Cost
                     then
                        Upgrade (K, T);
                        Done := Done + 1;
                        exit;
                     end if;
                  end loop;
               end loop;
               Put_Line ("  upgrades bought:" & Done'Image
                         & ", prestige left" & C.Prestige'Image);
            end;
         end loop;
         Put_Line ("  " & To_String (Report));
      end loop;
   end;
end Selftest;
