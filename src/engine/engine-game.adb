with Ada.Numerics.Float_Random;
with Ada.Strings.Fixed;
with Ada.Characters.Handling;  use Ada.Characters.Handling;

package body Engine.Game is

   package FR renames Ada.Numerics.Float_Random;
   Gen : FR.Generator;

   function Img (N : Integer) return String is
      S : constant String := Integer'Image (N);
   begin
      return (if N < 0 then S else S (S'First + 1 .. S'Last));
   end Img;

   ---------
   -- Log --
   ---------

   procedure Log (S : String) is
   begin
      Messages.Append (S);
   end Log;

   procedure Queue_Hint (H : in out Hint) is
   begin
      H.Shown := True;
      Pending_Hints.Append (To_String (H.Text));
   end Queue_Hint;

   procedure Raise_Event (Name : String) is
   begin
      if not G.Loaded or else G.Sides (G.Current).Control /= Human then
         return;
      end if;
      for H of G.Hints loop
         if not H.Shown and then H.Turn = 0
           and then To_String (H.Event) = Name
         then
            Queue_Hint (H);
         end if;
      end loop;
   end Raise_Event;

   function Unit_Name (U : Unit_Index) return String is
     (To_String (G.Sides (G.Units (U).Side).Name) & " "
      & To_String (Type_Of (U).Name));

   function Find_Type (Id : String) return Natural is
   begin
      for I in G.Types.First_Index .. G.Types.Last_Index loop
         if To_Lower (To_String (G.Types (I).Id)) = To_Lower (Id) then
            return I;
         end if;
      end loop;
      return 0;
   end Find_Type;

   --  Ships do not exert a zone of control on land.
   function Zoc_Enemy (U : Natural; Side : Player_Side) return Boolean is
     (Is_Enemy (U, Side) and then not Is_Naval (U));

   function Enemy_Adjacent (H : Hex; Side : Player_Side) return Boolean is
   begin
      for D in Direction loop
         if Zoc_Enemy (Unit_At (Neighbor (H, D)), Side) then
            return True;
         end if;
      end loop;
      return False;
   end Enemy_Adjacent;

   function Is_Surrounded (U : Unit_Index) return Boolean is
      Un : constant Unit      := G.Units (U);
      T  : constant Unit_Type := G.Types (Un.Kind);
   begin
      if not Un.Alive or else Is_Air (T) or else T.Mover in Static | Naval
      then
         return False;
      end if;
      for D in Direction loop
         declare
            N : constant Hex := Neighbor (Un.Pos, D);
         begin
            if In_Map (N)
              and then Move_Cost (Terrain_At (N), T.Mover) < Impassable
              and then not Is_Enemy (Unit_At (N), Un.Side)
              and then not Enemy_Adjacent (N, Un.Side)
            then
               return False;          --  a way out
            end if;
         end;
      end loop;
      return Enemy_Adjacent (Un.Pos, Un.Side);
   end Is_Surrounded;

   ------------
   -- Vision --
   ------------

   procedure Mark_Seen (S : Player_Side; Center : Hex; Radius : Natural) is
   begin
      for C in Center.Col - Radius .. Center.Col + Radius loop
         for R in Center.Row - Radius - 1 .. Center.Row + Radius + 1 loop
            if In_Map ((C, R)) and then Distance ((C, R), Center) <= Radius
            then
               G.Seen (S) (C, R) := True;
            end if;
         end loop;
      end loop;
   end Mark_Seen;

   --  Sight radius of a unit type in the current weather.
   function Eff_Spot (T : Unit_Type) return Natural is
     (case G.Weather is
         when Fair | Overcast => T.Spot,
         when Rain | Snow     => Natural'Max (1, T.Spot - 1),
         when Mist            => 1);

   procedure Update_Vision is
   begin
      for S in Player_Side loop
         G.Seen (S) := (others => (others => False));
      end loop;
      for U of G.Units loop
         if U.Alive then
            Mark_Seen (U.Side, U.Pos, Eff_Spot (G.Types (U.Kind)));
         end if;
      end loop;
      for C in 0 .. G.Cols - 1 loop
         for R in 0 .. G.Rows - 1 loop
            if G.Cells (C, R).Owner /= 0 then
               Mark_Seen (G.Cells (C, R).Owner, (C, R), 1);
            end if;
         end loop;
      end loop;
      --  Remember where enemies were last seen.
      for U of G.Units loop
         if U.Alive then
            for S in Player_Side loop
               if S /= U.Side and then G.Seen (S) (U.Pos.Col, U.Pos.Row) then
                  U.Seen_Pos (S)  := U.Pos;
                  U.Seen_Turn (S) := G.Turn;
               end if;
            end loop;
         end if;
      end loop;
      Update_Supply;
   end Update_Vision;

   function Visible (U : Unit_Index; By : Player_Side) return Boolean is
      Un : constant Unit := G.Units (U);
   begin
      return Un.Side = By or else not G.Fog
        or else G.Seen (By) (Un.Pos.Col, Un.Pos.Row);
   end Visible;

   function Known (U : Unit_Index; By : Player_Side) return Boolean is
     ((G.Sides (By).Control = Computer and then not G.Fair_AI)
      or else Visible (U, By));

   Memory_Turns : constant := 3;

   function Remembered (U : Unit_Index; By : Player_Side) return Boolean is
     (Known (U, By)
      or else (G.Units (U).Alive
               and then G.Turn - G.Units (U).Seen_Turn (By) <= Memory_Turns));

   function Believed_Pos (U : Unit_Index; By : Player_Side) return Hex is
     (if Known (U, By) then G.Units (U).Pos else G.Units (U).Seen_Pos (By));

   procedure Add_Fx (E : Fx_Event) is
   begin
      if Record_Effects then
         Effects.Append (E);
      end if;
   end Add_Fx;

   function Known_Enemy (U : Natural; Side : Player_Side) return Boolean is
     (Is_Enemy (U, Side) and then Known (U, Side));

   function Known_Enemy_Adjacent (H : Hex; Side : Player_Side)
                                  return Boolean is
   begin
      for D in Direction loop
         if Known_Enemy (Unit_At (Neighbor (H, D)), Side)
           and then not Is_Naval (Unit_At (Neighbor (H, D)))
         then
            return True;
         end if;
      end loop;
      return False;
   end Known_Enemy_Adjacent;


   -------------
   -- Weather --
   -------------

   function Weather_Name (W : Weather_Kind) return String is
     (case W is
         when Fair     => "Fair",
         when Overcast => "Overcast",
         when Rain     => "Rain",
         when Snow     => "Snow",
         when Mist     => "Fog");

   function Weather_Effects (W : Weather_Kind) return String is
     (case W is
         when Fair     => "no effects",
         when Overcast => "air attacks weakened",
         when Rain     => "aircraft grounded, mud slows vehicles off-road",
         when Snow     => "aircraft grounded, all movement slowed off-road",
         when Mist     => "aircraft grounded, sight 1 hex, poor ranged fire");

   function Climate_Name (C : Climate_Kind) return String is
     (case C is
         when Always_Fair => "fair",
         when Temperate   => "temperate",
         when Wet         => "wet",
         when Winter      => "winter");

   function Weather_Penalty (T : Terrain_Kind; M : Move_Class) return Natural
   is
   begin
      if M in Air | Naval | Static
        or else T in Road | Town | City | Fortress | Airfield
        or else Move_Cost (T, M) >= Impassable
      then
         return 0;
      end if;
      case G.Weather is
         when Rain =>
            return (if M in Wheeled | Tracked then 1 else 0);
         when Snow =>
            return 1;
         when others =>
            return 0;
      end case;
   end Weather_Penalty;

   function Roll_Weather (Turn : Positive) return Weather_Kind is
      R : Float;
   begin
      for P of G.Weather_Plan loop
         if P.Turn = Turn then
            return P.Kind;
         end if;
      end loop;
      R := FR.Random (Gen);
      case G.Climate is
         when Always_Fair =>
            return Fair;
         when Temperate =>
            return (if R < 0.60 then Fair elsif R < 0.85 then Overcast
                    else Rain);
         when Wet =>
            return (if R < 0.30 then Fair elsif R < 0.60 then Overcast
                    elsif R < 0.92 then Rain else Mist);
         when Winter =>
            return (if R < 0.35 then Fair elsif R < 0.60 then Overcast
                    elsif R < 0.92 then Snow else Mist);
      end case;
   end Roll_Weather;

   procedure Announce_Weather is
   begin
      Log ("Weather: " & Weather_Name (G.Weather) & " ("
           & Weather_Effects (G.Weather) & "). Forecast: "
           & Weather_Name (G.Forecast));
   end Announce_Weather;

   ------------
   -- Supply --
   ------------

   function Supply_Name (L : Supply_Level) return String is
     (case L is
         when Supplied   => "in supply",
         when Low_Supply => "low supply",
         when Cut_Off    => "OUT OF SUPPLY");

   function Edge_Name (E : Edge_Kind) return String is
     (case E is
         when Auto    => "auto",
         when No_Edge => "none",
         when West    => "west",
         when East    => "east",
         when North   => "north",
         when South   => "south");

   function On_Edge (H : Hex; E : Edge_Kind) return Boolean is
     (case E is
         when West    => H.Col = 0,
         when East    => H.Col = G.Cols - 1,
         when North   => H.Row = 0,
         when South   => H.Row = G.Rows - 1,
         when others  => False);

   procedure Update_Supply is
      Limit : constant Natural := 2 * G.Era.Supply_Range;
   begin
      for S in Player_Side loop
         declare
            Grid : Int_Grid renames G.Supply (S);
         begin
            Grid := (others => (others => -1));
            --  Sources.
            for C in 0 .. G.Cols - 1 loop
               for R in 0 .. G.Rows - 1 loop
                  declare
                     H  : constant Hex := (C, R);
                     Ce : constant Cell := G.Cells (C, R);
                  begin
                     if not Is_Enemy (Ce.Occupant, S)
                       and then ((Ce.Owner = S
                                  and then Is_Capturable (Ce.Terrain))
                                 or else (On_Edge (H, G.Supply_Edge (S))
                                          and then Move_Cost (Ce.Terrain, Foot)
                                                   < Impassable))
                     then
                        Grid (C, R) := 0;
                     end if;
                  end;
               end loop;
            end loop;
            --  Spread by cost levels, like Compute_Reach.
            for Level in 0 .. Limit loop
               for C in 0 .. G.Cols - 1 loop
                  for R in 0 .. G.Rows - 1 loop
                     if Grid (C, R) = Level then
                        declare
                           H   : constant Hex := (C, R);
                           Occ : constant Natural := Unit_At (H);
                        begin
                           if (Occ /= No_Unit and then G.Units (Occ).Side = S)
                             or else not Enemy_Adjacent (H, S)
                           then
                              for D in Direction loop
                                 declare
                                    N : constant Hex := Neighbor (H, D);
                                    Step, New_Cost : Natural;
                                 begin
                                    if In_Map (N)
                                      and then not Is_Enemy (Unit_At (N), S)
                                    then
                                       Step :=
                                         Move_Cost (Terrain_At (N), Foot);
                                       New_Cost := Level + Step;
                                       if Step < Impassable
                                         and then New_Cost <= Limit
                                         and then (Grid (N.Col, N.Row) < 0
                                                   or else Grid (N.Col, N.Row)
                                                           > New_Cost)
                                       then
                                          Grid (N.Col, N.Row) := New_Cost;
                                       end if;
                                    end if;
                                 end;
                              end loop;
                           end if;
                        end;
                     end if;
                  end loop;
               end loop;
            end loop;
         end;
      end loop;
   end Update_Supply;

   function Supply_At (H : Hex; Side : Player_Side) return Supply_Level is
      V : Integer;
   begin
      if not In_Map (H) then
         return Cut_Off;
      end if;
      V := G.Supply (Side) (H.Col, H.Row);
      if V < 0 then
         return Cut_Off;
      elsif V <= G.Era.Supply_Range then
         return Supplied;
      else
         return Low_Supply;
      end if;
   end Supply_At;

   --  Aircraft, ships and fortifications carry their own stocks.
   function Unit_Supply (Un : Unit) return Supply_Level is
     (if G.Types (Un.Kind).Mover in Air | Naval | Static then Supplied
      else Supply_At (Un.Pos, Un.Side));

   function Supply_Of (U : Unit_Index) return Supply_Level is
     (Unit_Supply (G.Units (U)));

   --------------
   -- Movement --
   --------------

   function Slot_At (H : Hex; Air_Layer : Boolean) return Natural is
     (if Air_Layer then Air_At (H) else Unit_At (H));

   procedure Compute_Reach (U : Unit_Index; R : out Reach_Map) is
      Un     : constant Unit      := G.Units (U);
      T      : constant Unit_Type := G.Types (Un.Kind);
      Flying : constant Boolean   := Is_Air (T);
      Budget : Natural := Un.Moves_Left;
   begin
      R := (others => <>);
      if not Un.Alive then
         return;
      end if;
      R.Cost (Un.Pos.Col, Un.Pos.Row) := 0;
      if T.Max_Fuel > 0 then
         Budget := Natural'Min (Budget, Un.Fuel);
      end if;
      if T.Mover = Static or else (Flying and then Grounded) then
         return;
      end if;

      --  Dijkstra by cost levels (all step costs are >= 1).
      for Level in 0 .. Budget loop
         for C in 0 .. G.Cols - 1 loop
            for Rw in 0 .. G.Rows - 1 loop
               if R.Cost (C, Rw) = Level then
                  declare
                     H : constant Hex := (C, Rw);
                  begin
                     --  Entering a (known) enemy zone of control ends
                     --  movement. Aircraft ignore it.
                     if Flying or else H = Un.Pos
                       or else not Known_Enemy_Adjacent (H, Un.Side)
                     then
                        for D in Direction loop
                           declare
                              N    : constant Hex := Neighbor (H, D);
                              Step : Natural;
                              New_Cost : Natural;
                           begin
                              if In_Map (N)
                                and then (Flying
                                          or else not Known_Enemy
                                            (Unit_At (N), Un.Side))
                              then
                                 Step := Move_Cost (Terrain_At (N), T.Mover)
                                   + Weather_Penalty (Terrain_At (N),
                                                      T.Mover);
                                 New_Cost := Level + Step;
                                 if Step < Impassable
                                   and then New_Cost <= Budget
                                   and then (R.Cost (N.Col, N.Row) < 0
                                             or else R.Cost (N.Col, N.Row)
                                                     > New_Cost)
                                 then
                                    R.Cost (N.Col, N.Row) := New_Cost;
                                    R.Parent (N.Col, N.Row) := C * 100 + Rw;
                                 end if;
                              end if;
                           end;
                        end loop;
                     end if;
                  end;
               end if;
            end loop;
         end loop;
      end loop;
   end Compute_Reach;

   function Can_Move_To
     (U : Unit_Index; R : Reach_Map; H : Hex) return Boolean
   is
      Flying : constant Boolean := Is_Air (U);
      O      : Natural;
   begin
      if not In_Map (H) or else G.Units (U).Pos = H
        or else R.Cost (H.Col, H.Row) <= 0
      then
         return False;
      end if;
      O := Slot_At (H, Flying);
      --  A hidden enemy looks like an empty hex.
      return O = No_Unit
        or else (Is_Enemy (O, G.Units (U).Side)
                 and then not Known (O, G.Units (U).Side));
   end Can_Move_To;

   type Undo_State is record
      Valid  : Boolean := False;
      U      : Natural := 0;
      Before : Unit;
   end record;
   Undo : Undo_State;

   procedure Capture (H : Hex; Side : Player_Side) is
      C : Cell renames G.Cells (H.Col, H.Row);
   begin
      Undo.Valid := False;
      if (Is_Capturable (C.Terrain) or else C.Victory)
        and then C.Owner /= Side
      then
         C.Owner := Side;
         if C.Victory then
            G.Sides (Side).Prestige := G.Sides (Side).Prestige + 50;
         else
            G.Sides (Side).Prestige := G.Sides (Side).Prestige + 15;
         end if;
         Log (To_String (G.Sides (Side).Name) & " captures "
              & (if Length (C.Name) > 0 then To_String (C.Name)
                 else Name (C.Terrain))
              & (if C.Victory then " (objective!)" else ""));
         Raise_Event ("capture");
         declare
            E : Fx_Event;
         begin
            E.Kind := Fx_Capture;
            E.To   := H;
            Add_Fx (E);
         end;
      end if;
   end Capture;

   function Can_Undo return Boolean is
     (Undo.Valid and then Undo.U /= 0 and then G.Units (Undo.U).Alive);

   function Visible_Enemies (Side : Player_Side) return Natural is
      N : Natural := 0;
   begin
      for I in G.Units.First_Index .. G.Units.Last_Index loop
         if G.Units (I).Alive and then G.Units (I).Side /= Side
           and then Visible (I, Side)
         then
            N := N + 1;
         end if;
      end loop;
      return N;
   end Visible_Enemies;

   procedure Move_Unit (U : Unit_Index; To : Hex; R : Reach_Map) is
      Un      : Unit renames G.Units (U);
      T       : constant Unit_Type := G.Types (Un.Kind);
      Flying  : constant Boolean := Is_Air (T);
      Path    : array (1 .. 200) of Hex;
      Len     : Natural := 0;
      H       : Hex := To;
      Reached : Hex := Un.Pos;     --  last free hex we can stop in
      Stopped : Boolean := False;
      Cost    : Natural;
   begin
      if not Can_Move_To (U, R, To) then
         return;
      end if;
      Undo.Valid := False;
      --  Rebuild the path (destination back to start).
      while H /= Un.Pos and then Len < Path'Last loop
         Len := Len + 1;
         Path (Len) := H;
         declare
            P : constant Integer := R.Parent (H.Col, H.Row);
         begin
            exit when P < 0;
            H := (P / 100, P mod 100);
         end;
      end loop;

      --  Walk it, start to destination.
      for I in reverse 1 .. Len loop
         declare
            N : constant Hex := Path (I);
            O : constant Natural := Slot_At (N, Flying);
         begin
            if Is_Enemy (O, Un.Side) then
               --  Bumped into a hidden enemy.
               G.Seen (Un.Side) (N.Col, N.Row) := True;
               Log (Unit_Name (U) & " runs into hidden "
                    & To_String (Type_Of (O).Name) & " - ambush!");
               Raise_Event ("ambush");
               Stopped := True;
               exit;
            end if;
            if O = No_Unit then
               Reached := N;
            end if;
            Mark_Seen (Un.Side, N, Eff_Spot (T));
            if not Flying and then I > 1 and then O = No_Unit
              and then Enemy_Adjacent (N, Un.Side)
            then
               Log (Unit_Name (U) & " makes contact with the enemy");
               Raise_Event ("contact");
               Stopped := True;
               exit;
            end if;
         end;
      end loop;

      if Reached = Un.Pos then
         Un.Moves_Left := 0;
         Un.Has_Moved  := True;
         Update_Vision;
         return;
      end if;

      Cost := R.Cost (Reached.Col, Reached.Row);
      if Flying then
         G.Cells (Un.Pos.Col, Un.Pos.Row).Air := No_Unit;
         G.Cells (Reached.Col, Reached.Row).Air := U;
      else
         G.Cells (Un.Pos.Col, Un.Pos.Row).Occupant := No_Unit;
         G.Cells (Reached.Col, Reached.Row).Occupant := U;
      end if;
      --  Animation path: start .. Reached.
      declare
         E : Fx_Event;
      begin
         E.Kind := Fx_Move;
         E.Unit := U;
         E.Len  := 1;
         E.Path (1) := Un.Pos;
         for I in reverse 1 .. Len loop
            exit when E.Len = Max_Fx_Path;
            E.Len := E.Len + 1;
            E.Path (E.Len) := Path (I);
            exit when Path (I) = Reached;
         end loop;
         Add_Fx (E);
      end;
      Un.Pos := Reached;
      if T.Max_Fuel > 0 then
         Un.Fuel := Un.Fuel - Natural'Min (Un.Fuel, Cost);
      end if;
      --  Recon and aircraft may split their move; everybody else is done.
      if not Stopped and then (T.Class = Recon or else Flying)
        and then (Flying or else not Enemy_Adjacent (Reached, Un.Side))
      then
         Un.Moves_Left := Un.Moves_Left - Natural'Min (Un.Moves_Left, Cost);
      else
         Un.Moves_Left := 0;
      end if;
      Un.Has_Moved := True;
      Un.Entrench  := 0;
      if not Flying and then not Is_Naval (T) then
         Capture (Reached, Un.Side);
      end if;
      Update_Vision;
      Raise_Event ("move");
      Check_Victory;
   end Move_Unit;

   procedure Move_Unit_Undoable (U : Unit_Index; To : Hex; R : Reach_Map)
   is
      Side   : constant Player_Side := G.Units (U).Side;
      Before : constant Unit := G.Units (U);
      Seen_Before : constant Natural := Visible_Enemies (Side);
      Owner_Before : constant Side_Id :=
        (if In_Map (To) then G.Cells (To.Col, To.Row).Owner else 0);
   begin
      Move_Unit (U, To, R);
      if G.Units (U).Pos = To and then G.Winner = 0
        and then Visible_Enemies (Side) <= Seen_Before
        and then G.Cells (To.Col, To.Row).Owner = Owner_Before
      then
         Undo := (Valid => True, U => U, Before => Before);
      else
         Undo.Valid := False;
      end if;
   end Move_Unit_Undoable;

   procedure Undo_Move is
   begin
      if not Can_Undo then
         return;
      end if;
      declare
         U   : constant Unit_Index := Undo.U;
         Now : constant Hex := G.Units (U).Pos;
         Old : constant Unit := Undo.Before;
      begin
         if Is_Air (U) then
            G.Cells (Now.Col, Now.Row).Air := No_Unit;
            G.Cells (Old.Pos.Col, Old.Pos.Row).Air := U;
         else
            G.Cells (Now.Col, Now.Row).Occupant := No_Unit;
            G.Cells (Old.Pos.Col, Old.Pos.Row).Occupant := U;
         end if;
         G.Units (U) := Old;
         Undo.Valid := False;
         Update_Vision;
         Log (Unit_Name (U) & " move undone");
      end;
   end Undo_Move;

   ------------
   -- Combat --
   ------------

   function Can_Attack_From
     (A : Unit_Index; From : Hex; D : Unit_Index) return Boolean
   is
      AU   : constant Unit      := G.Units (A);
      DU   : constant Unit      := G.Units (D);
      ATy  : constant Unit_Type := G.Types (AU.Kind);
      DTy  : constant Unit_Type := G.Types (DU.Kind);
      Dist : constant Natural   := Distance (From, DU.Pos);
   begin
      if not AU.Alive or else not DU.Alive or else AU.Side = DU.Side
        or else AU.Has_Attacked or else AU.Ammo = 0
        or else Dist > ATy.Max_Range
        or else Attack_Stat (ATy, DTy.Target) = 0
        or else not Known (D, AU.Side)
      then
         return False;
      end if;
      --  Same hex only between air and ground (aircraft overhead).
      if Dist = 0 and then Is_Air (ATy) = Is_Air (DTy) then
         return False;
      end if;
      --  No sorties in rain, snow or fog.
      if Is_Air (ATy) and then Grounded then
         return False;
      end if;
      --  Guns must be emplaced: no firing after a move.
      if ATy.Class = Artillery and then (AU.Has_Moved or else From /= AU.Pos)
      then
         return False;
      end if;
      return True;
   end Can_Attack_From;

   function Target_In (A : Unit_Index; H : Hex) return Natural is
      Gr   : constant Natural := Unit_At (H);
      Ai   : constant Natural := Air_At (H);
      Ok_G : constant Boolean := Gr /= No_Unit and then Can_Attack (A, Gr);
      Ok_A : constant Boolean := Ai /= No_Unit and then Can_Attack (A, Ai);
   begin
      if Ok_G and then Ok_A then
         return (if Type_Of (A).Class in Fighter | Anti_Air then Ai else Gr);
      elsif Ok_G then
         return Gr;
      elsif Ok_A then
         return Ai;
      end if;
      return No_Unit;
   end Target_In;

   function Eff_Strength (U : Unit) return Natural is
     (U.Strength - Natural'Min (U.Strength, U.Suppressed));

   --  Attack value of A (at From) against D.
   function Attack_Value
     (A : Unit; From : Hex; D : Unit) return Integer
   is
      ATy  : constant Unit_Type    := G.Types (A.Kind);
      DTy  : constant Unit_Type    := G.Types (D.Kind);
      DTer : constant Terrain_Kind := Terrain_At (D.Pos);
      Dist : constant Natural      := Distance (From, D.Pos);
      V    : Integer := Attack_Stat (ATy, DTy.Target) + Exp_Level (A);
   begin
      if Unit_Supply (A) = Cut_Off then
         V := V - 1;
      end if;
      if Is_Air (ATy) and then G.Weather = Overcast then
         V := V - 2;
      elsif Dist >= 2 then
         --  Observed fire suffers in poor visibility.
         V := V - (case G.Weather is
                      when Fair | Overcast => 0,
                      when Rain | Snow     => 1,
                      when Mist            => 2);
      end if;
      if Dist = 1 and then not Is_Air (ATy) and then not Is_Air (DTy) then
         if ATy.Mover in Wheeled | Tracked and then Is_Close (DTer) then
            V := V - G.Era.Close_Armor_Penalty;
         end if;
         if Terrain_At (From) = River then
            V := V - 2;
         end if;
         if ATy.Charge and then not Is_Close (DTer)
           and then D.Entrench <= 1
         then
            V := V + G.Era.Charge_Bonus;
         end if;
      end if;
      return V;
   end Attack_Value;

   function Defense_Value
     (D : Unit; A : Unit; Dist : Natural; In_Place : Boolean) return Integer
   is
      ATy : constant Unit_Type := G.Types (A.Kind);
      DTy : constant Unit_Type := G.Types (D.Kind);
      V   : Integer := DTy.Defense + Exp_Level (D);
   begin
      if In_Place and then Unit_Supply (D) = Cut_Off then
         V := V - 1;
      end if;
      if In_Place and then not Is_Air (DTy) then
         if Is_Air (ATy) then
            V := V + Defense_Bonus (Terrain_At (D.Pos)) / 2;
         else
            V := V + Defense_Bonus (Terrain_At (D.Pos));
            if not ATy.Ignore_Entrench then
               V := V + D.Entrench;
            end if;
         end if;
      end if;
      if Dist = 1 and then ATy.Class = Cavalry
        and then DTy.Class in Infantry | Engineer
      then
         V := V + G.Era.Square_Bonus;
      end if;
      if In_Place and then D.Alive
        and then G.Cells (D.Pos.Col, D.Pos.Row).Occupant /= No_Unit
        and then Is_Surrounded (G.Cells (D.Pos.Col, D.Pos.Row).Occupant)
        and then G.Units (G.Cells (D.Pos.Col, D.Pos.Row).Occupant).Pos = D.Pos
        and then not Is_Air (DTy)
      then
         V := V - 2;
      end if;
      return V;
   end Defense_Value;

   function Hit_Chance (Diff : Integer) return Float is
      P : constant Float := 0.25 + 0.05 * Float (Diff);
   begin
      return Float'Max (0.05, Float'Min (0.80, P));
   end Hit_Chance;

   function Roll_Hits (Shots : Natural; P : Float) return Natural is
      N : Natural := 0;
   begin
      for I in 1 .. Shots loop
         if FR.Random (Gen) < P then
            N := N + 1;
         end if;
      end loop;
      return N;
   end Roll_Hits;

   function Retaliates (D : Unit; A : Unit; From : Hex) return Boolean is
     (Distance (From, D.Pos) <= 1 and then D.Ammo > 0
      and then Attack_Stat (G.Types (D.Kind), G.Types (A.Kind).Target) > 0);

   function Retaliation_Shots (D : Unit) return Natural is
     (if G.Types (D.Kind).Class = Artillery then Eff_Strength (D) / 2
      else Eff_Strength (D));

   --  May S fire in support of D, against attacker A (at From)?
   function Supports (S : Unit; A : Unit; From : Hex; D : Unit)
                      return Boolean
   is
      ST  : constant Unit_Type := G.Types (S.Kind);
      ATy : constant Unit_Type := G.Types (A.Kind);
   begin
      if not S.Alive or else S.Side /= D.Side or else S.Pos = D.Pos
        or else S.Ammo = 0
      then
         return False;
      end if;
      if Is_Air (ATy) then
         return (ST.Support and then ST.Air_Attack > 0
                 and then Distance (S.Pos, From) <= ST.Max_Range
                 and then Distance (S.Pos, D.Pos) <= 2)
           or else (ST.Class = Fighter and then ATy.Class = Bomber
                    and then Distance (S.Pos, From) <= 3);
      else
         return ST.Support and then ST.Class = Artillery
           and then Distance (From, D.Pos) = 1
           and then Distance (S.Pos, From) <= ST.Max_Range
           and then Distance (S.Pos, D.Pos) <= 2;
      end if;
   end Supports;

   function Support_Threat (A : Unit_Index; From : Hex; D : Unit)
                            return Boolean is
   begin
      for I in G.Units.First_Index .. G.Units.Last_Index loop
         if Supports (G.Units (I), G.Units (A), From, D)
           and then Known (I, G.Units (A).Side)
         then
            return True;
         end if;
      end loop;
      return False;
   end Support_Threat;

   function Predict
     (A : Unit_Index; From : Hex; D : Unit_Index) return Prediction
   is
      AU    : constant Unit    := G.Units (A);
      DU    : constant Unit    := G.Units (D);
      Dist  : constant Natural := Distance (From, DU.Pos);
      P     : Prediction;
      Mover : Unit := AU;
   begin
      Mover.Pos := From;
      P.Def_Loss := Float (Eff_Strength (AU))
        * Hit_Chance (Attack_Value (AU, From, DU)
                      - Defense_Value (DU, AU, Dist, True));
      P.Def_Loss := Float'Min (P.Def_Loss, Float (DU.Strength));
      if Retaliates (DU, AU, From) then
         P.Att_Loss := Float (Retaliation_Shots (DU))
           * Hit_Chance (Attack_Value (DU, DU.Pos, Mover)
                         - Defense_Value (Mover, DU, Dist, False));
         P.Att_Loss := Float'Min (P.Att_Loss, Float (AU.Strength));
      end if;
      P.Support_Threat := Support_Threat (A, From, DU);
      return P;
   end Predict;

   procedure Clear_Slot (U : Unit_Index) is
      Un : constant Unit := G.Units (U);
   begin
      if Is_Air (U) then
         if G.Cells (Un.Pos.Col, Un.Pos.Row).Air = U then
            G.Cells (Un.Pos.Col, Un.Pos.Row).Air := No_Unit;
         end if;
      elsif G.Cells (Un.Pos.Col, Un.Pos.Row).Occupant = U then
         G.Cells (Un.Pos.Col, Un.Pos.Row).Occupant := No_Unit;
      end if;
   end Clear_Slot;

   procedure Destroy (U : Unit_Index) is
      E : Fx_Event;
   begin
      E.Kind := Fx_Destroyed;
      E.Unit := U;
      E.To   := G.Units (U).Pos;
      Add_Fx (E);
      Clear_Slot (U);
      G.Units (U).Alive    := False;
      G.Units (U).Strength := 0;
      Log ("  " & Unit_Name (U) & " is destroyed!");
   end Destroy;

   procedure Remove_Unit (U : Unit_Index) is
   begin
      Clear_Slot (U);
      G.Units (U).Alive := False;
   end Remove_Unit;

   procedure Attack (A, D : Unit_Index) is
      ATy  : constant Unit_Type := Type_Of (A);
      DTy  : constant Unit_Type := Type_Of (D);
      Dist : Natural;
      Att_Hits, Def_Hits : Natural := 0;
      Support_Fired : Natural := 0;
      Support_Losses : Natural := 0;
      Human_Attacker : constant Boolean :=
        G.Sides (G.Units (A).Side).Control = Human;
   begin
      if not Can_Attack (A, D) then
         return;
      end if;
      Undo.Valid := False;
      Dist := Distance (G.Units (A).Pos, G.Units (D).Pos);
      Log (Unit_Name (A) & " attacks " & Unit_Name (D)
           & (if Is_Surrounded (D) then " (surrounded!)" else ""));

      --  Defensive support fire: guns, flak, intercepting fighters.
      for S in G.Units.First_Index .. G.Units.Last_Index loop
         exit when Support_Fired >= 2;
         if S /= D
           and then Supports (G.Units (S), G.Units (A), G.Units (A).Pos,
                              G.Units (D))
         then
            declare
               SU : Unit renames G.Units (S);
               ST : constant Unit_Type := G.Types (SU.Kind);
               Factor : constant Float :=
                 (if ST.Class = Fighter then 0.8 else 0.6);
               H : constant Natural :=
                 Natural'Min
                   (G.Units (A).Strength,
                    Roll_Hits
                      (Eff_Strength (SU),
                       Hit_Chance
                         (Attack_Value (SU, SU.Pos, G.Units (A))
                          - Defense_Value (G.Units (A), SU, 2, False))
                       * Factor));
            begin
               SU.Ammo := SU.Ammo - 1;
               Support_Fired := Support_Fired + 1;
               Support_Losses := Support_Losses + H;
               G.Units (A).Strength := G.Units (A).Strength - H;
               Log ("  " & (if ST.Class = Fighter then "Interception by "
                            else "Support fire from ")
                    & To_String (ST.Name)
                    & ": attacker loses" & Natural'Image (H));
            end;
         end if;
      end loop;
      if G.Units (A).Strength = 0 then
         Destroy (A);
         Update_Vision;
         Check_Victory;
         return;
      end if;

      declare
         AU : Unit renames G.Units (A);
         DU : Unit renames G.Units (D);
      begin
         --  Simultaneous fire, using strengths before losses.
         Def_Hits := Roll_Hits
           (Eff_Strength (AU),
            Hit_Chance (Attack_Value (AU, AU.Pos, DU)
                        - Defense_Value (DU, AU, Dist, True)));
         if Retaliates (DU, AU, AU.Pos) then
            Att_Hits := Roll_Hits
              (Retaliation_Shots (DU),
               Hit_Chance (Attack_Value (DU, DU.Pos, AU)
                           - Defense_Value (AU, DU, Dist, False)));
            DU.Ammo := DU.Ammo - 1;
         end if;

         Def_Hits := Natural'Min (Def_Hits, DU.Strength);
         Att_Hits := Natural'Min (Att_Hits, AU.Strength);

         AU.Ammo         := AU.Ammo - 1;
         AU.Has_Attacked := True;
         if ATy.Class /= Recon and then not Is_Air (ATy) then
            AU.Moves_Left := 0;
         end if;
         AU.Strength := AU.Strength - Att_Hits;
         DU.Strength := DU.Strength - Def_Hits;
         --  Every attack shakes the defenders; a barrage even more so.
         DU.Entrench := DU.Entrench
           - Natural'Min (DU.Entrench, (if ATy.Bombard then 2 else 1));
         if ATy.Bombard or else ATy.Class = Bomber then
            DU.Suppressed := Natural'Min (DU.Strength,
                                          DU.Suppressed + Def_Hits);
         end if;
         AU.Experience := Natural'Min
           (Max_Experience, AU.Experience + 10 + 5 * Def_Hits);
         DU.Experience := Natural'Min
           (Max_Experience, DU.Experience + 5 + 5 * Att_Hits);

         Log ("  Result: attacker -" & Img (Att_Hits)
              & ", defender -" & Img (Def_Hits));
         declare
            E : Fx_Event;
         begin
            E.Kind   := Fx_Combat;
            E.Unit   := A;
            E.From   := AU.Pos;
            E.To     := DU.Pos;
            E.A_Loss := Att_Hits + Support_Losses;
            E.D_Loss := Def_Hits;
            E.Kind_Of_Fire := ATy.Class;
            E.Air_Attack   := Is_Air (ATy);
            Add_Fx (E);
         end;
      end;

      if G.Units (D).Strength = 0 then
         G.Sides (G.Units (A).Side).Prestige :=
           G.Sides (G.Units (A).Side).Prestige + DTy.Cost / 10;
         Destroy (D);
         if Human_Attacker then
            Raise_Event ("kill");
         end if;
      end if;
      if G.Units (A).Strength = 0 then
         G.Sides (G.Units (D).Side).Prestige :=
           G.Sides (G.Units (D).Side).Prestige + ATy.Cost / 10;
         Destroy (A);
         if Human_Attacker then
            Raise_Event ("loss");
         end if;
      end if;
      if Human_Attacker then
         Raise_Event ("attack");
      end if;
      Update_Vision;
      Check_Victory;
   end Attack;

   ----------------------
   -- Supply & reserve --
   ----------------------

   function On_Own_Base (U : Unit_Index) return Boolean is
      Un : constant Unit := G.Units (U);
      C  : constant Cell := G.Cells (Un.Pos.Col, Un.Pos.Row);
   begin
      if Is_Naval (U) then
         --  Ships replenish next to an own port.
         for D in Direction loop
            declare
               N : constant Hex := Neighbor (Un.Pos, D);
            begin
               if In_Map (N) and then G.Cells (N.Col, N.Row).Owner = Un.Side
                 and then Terrain_At (N) in Town | City | Fortress
               then
                  return True;
               end if;
            end;
         end loop;
         return False;
      end if;
      return Is_Capturable (C.Terrain) and then C.Owner = Un.Side;
   end On_Own_Base;

   function Can_Resupply (U : Unit_Index) return Boolean is
      Un : constant Unit      := G.Units (U);
      T  : constant Unit_Type := G.Types (Un.Kind);
   begin
      return Un.Alive and then Un.Side = G.Current
        and then not Un.Has_Moved and then not Un.Has_Attacked
        and then (T.Mover not in Air | Naval or else On_Own_Base (U))
        and then not Is_Surrounded (U)
        and then Supply_Of (U) /= Cut_Off
        and then (Un.Ammo < T.Max_Ammo or else Un.Fuel < T.Max_Fuel);
   end Can_Resupply;

   procedure Resupply (U : Unit_Index) is
      Un  : Unit renames G.Units (U);
      T   : constant Unit_Type := G.Types (Un.Kind);
      Cut : constant Boolean := Enemy_Adjacent (Un.Pos, Un.Side)
        or else Supply_Of (U) = Low_Supply;
   begin
      if not Can_Resupply (U) then
         return;
      end if;
      Undo.Valid := False;
      if Cut then
         Un.Ammo := Natural'Min (T.Max_Ammo, Un.Ammo + T.Max_Ammo / 2);
         Un.Fuel := Natural'Min (T.Max_Fuel, Un.Fuel + T.Max_Fuel / 2);
      else
         Un.Ammo := T.Max_Ammo;
         Un.Fuel := T.Max_Fuel;
      end if;
      Un.Has_Moved    := True;
      Un.Has_Attacked := True;
      Un.Moves_Left   := 0;
      Log (Unit_Name (U) & " resupplied"
           & (if Cut then " (partial: under pressure or low supply)"
              else ""));
      Raise_Event ("resupply");
   end Resupply;

   --  Strength points a reinforcement adds; fewer on low supply.
   function Reinforce_Gain (U : Unit_Index) return Natural is
     (Natural'Min ((if Supply_Of (U) = Low_Supply then 2 else 5),
                   Max_Strength - Natural'Min (Max_Strength,
                                               G.Units (U).Strength)));

   function Reinforce_Cost (U : Unit_Index) return Natural is
     (Reinforce_Gain (U) * Type_Of (U).Cost / 10);

   function Can_Reinforce (U : Unit_Index) return Boolean is
      Un : constant Unit := G.Units (U);
   begin
      return Un.Alive and then Un.Side = G.Current
        and then not Un.Has_Moved and then not Un.Has_Attacked
        and then Un.Strength < Max_Strength
        and then not Is_Surrounded (U)
        and then Supply_Of (U) /= Cut_Off
        and then (if Is_Air (U) or else Is_Naval (U) then On_Own_Base (U)
                  else not Enemy_Adjacent (Un.Pos, Un.Side))
        and then Reinforce_Cost (U) <= G.Sides (Un.Side).Prestige;
   end Can_Reinforce;

   procedure Reinforce (U : Unit_Index) is
      Un   : Unit renames G.Units (U);
      Gain : Natural;
   begin
      if not Can_Reinforce (U) then
         return;
      end if;
      Undo.Valid := False;
      Gain := Reinforce_Gain (U);
      G.Sides (Un.Side).Prestige :=
        G.Sides (Un.Side).Prestige - Reinforce_Cost (U);
      --  Green replacements dilute experience.
      Un.Experience := Un.Experience * Un.Strength / (Un.Strength + Gain);
      Un.Strength     := Un.Strength + Gain;
      Un.Has_Moved    := True;
      Un.Has_Attacked := True;
      Un.Moves_Left   := 0;
      Log (Unit_Name (U) & " reinforced +" & Img (Gain));
      Raise_Event ("reinforce");
   end Reinforce;

   --------------
   -- Purchase --
   --------------

   function May_Buy (T : Type_Index; Side : Player_Side) return Boolean is
      L : constant String := To_Lower (To_String (G.Sides (Side).Buy_List));
   begin
      if L = "none" then
         return False;
      end if;
      return G.Types (T).Buyable
        and then (L = ""
                  or else Ada.Strings.Fixed.Index
                    (L, "," & To_Lower (To_String (G.Types (T).Id)) & ",")
                    > 0);
   end May_Buy;

   function Can_Deploy
     (T : Type_Index; Side : Player_Side; H : Hex) return Boolean
   is
      Ty : constant Unit_Type := G.Types (T);
   begin
      if not In_Map (H) then
         return False;
      end if;
      declare
         C : constant Cell := G.Cells (H.Col, H.Row);
      begin
         if C.Owner /= Side or else not Is_Capturable (C.Terrain) then
            return False;
         end if;
         if Is_Air (Ty) then
            return C.Terrain in Airfield | City and then C.Air = No_Unit;
         end if;
         return C.Occupant = No_Unit and then not Enemy_Adjacent (H, Side)
           and then (Ty.Mover = Static
                     or else Move_Cost (C.Terrain, Ty.Mover) < Impassable);
      end;
   end Can_Deploy;

   function Has_Deploy_Hex (T : Type_Index; Side : Player_Side)
                            return Boolean is
   begin
      for C in 0 .. G.Cols - 1 loop
         for R in 0 .. G.Rows - 1 loop
            if Can_Deploy (T, Side, (C, R)) then
               return True;
            end if;
         end loop;
      end loop;
      return False;
   end Has_Deploy_Hex;

   procedure Buy (T : Type_Index; Side : Player_Side; H : Hex) is
      U  : Unit;
      Ty : constant Unit_Type := G.Types (T);
   begin
      if not May_Buy (T, Side) or else Ty.Cost > G.Sides (Side).Prestige
        or else not Can_Deploy (T, Side, H)
      then
         return;
      end if;
      G.Sides (Side).Prestige := G.Sides (Side).Prestige - Ty.Cost;
      Undo.Valid := False;
      U.Kind := T;
      U.Side := Side;
      U.Pos  := H;
      U.Ammo := Ty.Max_Ammo;
      U.Fuel := Ty.Max_Fuel;
      U.Moves_Left   := 0;
      U.Has_Moved    := True;
      U.Has_Attacked := True;
      U.Core         := True;
      Add_Unit (U);
      Log (To_String (G.Sides (Side).Name) & " deploys new "
           & To_String (Ty.Name)
           & (if Length (G.Cells (H.Col, H.Row).Name) > 0
              then " at " & To_String (G.Cells (H.Col, H.Row).Name)
              else ""));
      Update_Vision;
      Raise_Event ("buy");
      declare
         E : Fx_Event;
      begin
         E.Kind := Fx_Deploy;
         E.To   := H;
         Add_Fx (E);
      end;
   end Buy;

   ---------------
   -- Game flow --
   ---------------

   procedure Reset is
   begin
      G := (others => <>);
      Messages.Clear;
      Pending_Hints.Clear;
      Effects.Clear;
      Undo.Valid := False;
   end Reset;

   procedure Add_Unit (U : Unit) is
   begin
      G.Units.Append (U);
      if Is_Air (G.Types (U.Kind)) then
         G.Cells (U.Pos.Col, U.Pos.Row).Air := G.Units.Last_Index;
      else
         G.Cells (U.Pos.Col, U.Pos.Row).Occupant := G.Units.Last_Index;
      end if;
   end Add_Unit;

   procedure Place_Occupants is
   begin
      for C in Col_Range loop
         for R in Row_Range loop
            G.Cells (C, R).Occupant := No_Unit;
            G.Cells (C, R).Air      := No_Unit;
         end loop;
      end loop;
      for I in G.Units.First_Index .. G.Units.Last_Index loop
         declare
            U : constant Unit := G.Units (I);
         begin
            if U.Alive then
               if Is_Air (I) then
                  G.Cells (U.Pos.Col, U.Pos.Row).Air := I;
               else
                  G.Cells (U.Pos.Col, U.Pos.Row).Occupant := I;
               end if;
            end if;
         end;
      end loop;
   end Place_Occupants;

   function Income_Of (S : Player_Side) return Integer is
      Base : constant Integer := G.Sides (S).Income;
   begin
      --  Difficulty only scales the computer's income against a human.
      if G.Sides (S).Control = Computer
        and then G.Sides (Other (S)).Control = Human
      then
         case G.Difficulty is
            when Easy   => return Base * 6 / 10;
            when Normal => return Base;
            when Hard   => return Base * 14 / 10;
         end case;
      end if;
      return Base;
   end Income_Of;

   --  Nearest hex to H where a unit of type T can be placed.
   function Free_Spot (H : Hex; T : Positive) return Hex is
      Ty : constant Unit_Type := G.Types (T);
   begin
      for Ring in 0 .. 4 loop
         for C in H.Col - Ring .. H.Col + Ring loop
            for R in H.Row - Ring - 1 .. H.Row + Ring + 1 loop
               declare
                  P : constant Hex := (C, R);
               begin
                  if In_Map (P) and then Distance (P, H) = Ring
                    and then (if Is_Air (Ty) then Air_At (P) = No_Unit
                              else Unit_At (P) = No_Unit
                                and then (Ty.Mover = Static
                                          or else Move_Cost (Terrain_At (P),
                                                             Ty.Mover)
                                                  < Impassable))
                  then
                     return P;
                  end if;
               end;
            end loop;
         end loop;
      end loop;
      return No_Hex;
   end Free_Spot;

   procedure Arrivals (S : Player_Side) is
   begin
      for R of G.Reinforcements loop
         if not R.Done and then R.Side = S and then R.Turn <= G.Turn
           and then R.Kind <= Natural (G.Types.Length)
         then
            declare
               P : constant Hex := Free_Spot (R.Pos, R.Kind);
               U : Unit;
            begin
               if P /= No_Hex then
                  R.Done := True;
                  U.Kind := R.Kind;
                  U.Side := S;
                  U.Pos  := P;
                  U.Ammo := G.Types (R.Kind).Max_Ammo;
                  U.Fuel := G.Types (R.Kind).Max_Fuel;
                  U.Core := R.Core;
                  Add_Unit (U);
                  Log ("Reinforcements arrive for "
                       & To_String (G.Sides (S).Name) & ": "
                       & To_String (G.Types (R.Kind).Name)
                       & (if Length (G.Cells (P.Col, P.Row).Name) > 0
                          then " at " & To_String (G.Cells (P.Col, P.Row).Name)
                          else ""));
                  declare
                     E : Fx_Event;
                  begin
                     E.Kind := Fx_Deploy;
                     E.To   := P;
                     Add_Fx (E);
                  end;
               end if;
            end;
         end if;
      end loop;
   end Arrivals;

   procedure Begin_Side_Turn (S : Player_Side) is
      Arrived : constant Natural := Natural (G.Units.Length);
   begin
      Undo.Valid := False;
      G.Sides (S).Prestige := G.Sides (S).Prestige + Income_Of (S);
      Arrivals (S);
      Update_Vision;
      for I in G.Units.First_Index .. G.Units.Last_Index loop
         declare
            U : Unit renames G.Units (I);
         begin
            if U.Alive and then U.Side = S then
               --  Attrition: units cut off for more than a turn wither.
               if Unit_Supply (U) = Cut_Off then
                  U.Cut_Turns := U.Cut_Turns + 1;
                  if U.Cut_Turns >= 2 and then U.Strength > 1 then
                     U.Strength := U.Strength - 1;
                     Log (Unit_Name (I) & " is out of supply and loses"
                          & " strength");
                  end if;
               else
                  U.Cut_Turns := 0;
               end if;
            end if;
         end;
      end loop;
      for U of G.Units loop
         if U.Alive and then U.Side = S then
            if not U.Has_Moved and then not Is_Air (G.Types (U.Kind))
              and then not Is_Naval (G.Types (U.Kind))
            then
               U.Entrench := Natural'Min (U.Entrench + 1, G.Era.Max_Entrench);
            end if;
            U.Moves_Left   := G.Types (U.Kind).Movement;
            U.Has_Moved    := False;
            U.Has_Attacked := False;
            U.Suppressed   := 0;
         end if;
      end loop;
      Update_Vision;
      if Natural (G.Units.Length) > Arrived then
         Raise_Event ("reinforcements");
      end if;
      if G.Sides (S).Control = Human then
         for H of G.Hints loop
            if not H.Shown and then H.Turn = G.Turn then
               Queue_Hint (H);
            end if;
         end loop;
      end if;
   end Begin_Side_Turn;

   procedure Resolve_Supply_Edges is
      Sum_C, Sum_R : array (Player_Side) of Float := (others => 0.0);
      N            : array (Player_Side) of Natural := (others => 0);
      DC, DR       : Float;
   begin
      for U of G.Units loop
         if U.Alive and then G.Types (U.Kind).Mover not in Air | Naval then
            Sum_C (U.Side) := Sum_C (U.Side) + Float (U.Pos.Col);
            Sum_R (U.Side) := Sum_R (U.Side) + Float (U.Pos.Row);
            N (U.Side) := N (U.Side) + 1;
         end if;
      end loop;
      if N (1) = 0 or else N (2) = 0 or else G.Cols = 0 or else G.Rows = 0
      then
         for S in Player_Side loop
            if G.Supply_Edge (S) = Auto then
               G.Supply_Edge (S) := No_Edge;
            end if;
         end loop;
         return;
      end if;
      DC := (Sum_C (1) / Float (N (1)) - Sum_C (2) / Float (N (2)))
        / Float (G.Cols);
      DR := (Sum_R (1) / Float (N (1)) - Sum_R (2) / Float (N (2)))
        / Float (G.Rows);
      for S in Player_Side loop
         if G.Supply_Edge (S) = Auto then
            declare
               Sign : constant Float := (if S = 1 then 1.0 else -1.0);
            begin
               if abs DC >= abs DR then
                  G.Supply_Edge (S) :=
                    (if Sign * DC < 0.0 then West else East);
               else
                  G.Supply_Edge (S) :=
                    (if Sign * DR < 0.0 then North else South);
               end if;
            end;
         end if;
      end loop;
   end Resolve_Supply_Edges;

   procedure Start_Game is
   begin
      FR.Reset (Gen);
      for U of G.Units loop
         U.Ammo := G.Types (U.Kind).Max_Ammo;
         U.Fuel := G.Types (U.Kind).Max_Fuel;
      end loop;
      G.Turn    := 1;
      G.Current := G.First;
      G.Winner  := 0;
      G.Loaded  := True;
      G.Weather  := Roll_Weather (1);
      G.Forecast := Roll_Weather (2);
      Log ("=== " & To_String (G.Title) & " ===");
      Log ("Turn 1: " & To_String (G.Sides (G.Current).Name));
      Announce_Weather;
      Begin_Side_Turn (G.Current);
   end Start_Game;

   procedure Apply_Difficulty (D : Difficulty_Level) is
   begin
      G.Difficulty := D;
      for S in Player_Side loop
         if G.Sides (S).Control = Human
           and then G.Sides (Other (S)).Control = Computer
         then
            G.Sides (S).Prestige :=
              (case D is
                  when Easy   => G.Sides (S).Prestige * 3 / 2,
                  when Normal => G.Sides (S).Prestige,
                  when Hard   => G.Sides (S).Prestige * 3 / 4);
         elsif G.Sides (S).Control = Computer
           and then G.Sides (Other (S)).Control = Human
           and then D = Hard
         then
            --  Veteran opposition.
            for U of G.Units loop
               if U.Side = S then
                  U.Experience := Natural'Min (Max_Experience,
                                               U.Experience + 100);
               end if;
            end loop;
         end if;
      end loop;
   end Apply_Difficulty;

   function Victory_Hexes_Total return Natural is
      N : Natural := 0;
   begin
      for C in 0 .. G.Cols - 1 loop
         for R in 0 .. G.Rows - 1 loop
            if G.Cells (C, R).Victory then
               N := N + 1;
            end if;
         end loop;
      end loop;
      return N;
   end Victory_Hexes_Total;

   function Victory_Hexes_Owned (S : Player_Side) return Natural is
      N : Natural := 0;
   begin
      for C in 0 .. G.Cols - 1 loop
         for R in 0 .. G.Rows - 1 loop
            if G.Cells (C, R).Victory and then G.Cells (C, R).Owner = S then
               N := N + 1;
            end if;
         end loop;
      end loop;
      return N;
   end Victory_Hexes_Owned;

   procedure Declare_Winner (S : Player_Side; Why : String) is
      Total : constant Natural := Victory_Hexes_Total;
      Held  : constant Natural := Victory_Hexes_Owned (G.Attacker);
   begin
      if G.Winner = 0 then
         if Why = "enemy ground forces annihilated" then
            G.Decisive := True;
            G.Victory_Grade := To_Unbounded_String ("Decisive victory");
         elsif S = G.Attacker then
            G.Decisive := G.Turn <= (2 * G.Max_Turns + 2) / 3;
            G.Victory_Grade := To_Unbounded_String
              (if G.Decisive then "Decisive victory" else "Victory");
         else
            G.Decisive := Held = 0;
            G.Victory_Grade := To_Unbounded_String
              (if Held = 0 then "Decisive defensive victory"
               elsif 2 * Held >= Total then "Narrow defensive victory"
               else "Defensive victory");
         end if;
         G.Winner := S;
         Log ("*** " & To_String (G.Sides (S).Name) & " wins: " & Why);
         declare
            E : Fx_Event;
         begin
            E.Kind := Fx_Victory;
            E.Unit := Natural (S);
            Add_Fx (E);
         end;
      end if;
   end Declare_Winner;

   procedure Check_Victory is
      Alive : array (Player_Side) of Natural := (0, 0);
      Total : constant Natural := Victory_Hexes_Total;
   begin
      if G.Winner /= 0 then
         return;
      end if;
      if Total > 0 and then Victory_Hexes_Owned (G.Attacker) = Total then
         Declare_Winner (G.Attacker, "all objectives taken");
         return;
      end if;
      for U of G.Units loop
         if U.Alive and then not Is_Air (G.Types (U.Kind))
           and then not Is_Naval (G.Types (U.Kind))
         then
            Alive (U.Side) := Alive (U.Side) + 1;
         end if;
      end loop;
      for S in Player_Side loop
         if Alive (S) = 0 then
            Declare_Winner (Other (S), "enemy ground forces annihilated");
            return;
         end if;
      end loop;
   end Check_Victory;

   procedure End_Turn is
      Ending : constant Player_Side := G.Current;
   begin
      if G.Winner /= 0 then
         return;
      end if;
      --  Aircraft away from base burn fuel loitering; empty tanks crash.
      for I in G.Units.First_Index .. G.Units.Last_Index loop
         declare
            U : Unit renames G.Units (I);
         begin
            --  Grounded aircraft sit it out on a field strip.
            if U.Alive and then U.Side = Ending and then Is_Air (I)
              and then not On_Own_Base (I) and then not Grounded
            then
               if not U.Has_Moved then
                  U.Fuel := U.Fuel - Natural'Min (U.Fuel, 5);
               end if;
               if U.Fuel = 0 then
                  Log (Unit_Name (I) & " runs out of fuel and crashes!");
                  Destroy (I);
               end if;
            end if;
         end;
      end loop;

      G.Current := Other (G.Current);
      if G.Current = G.First then
         if G.Turn >= G.Max_Turns then
            Declare_Winner (Other (G.Attacker), "the attack ran out of time");
            return;
         end if;
         G.Turn := G.Turn + 1;
         declare
            Was : constant Weather_Kind := G.Weather;
         begin
            G.Weather  := G.Forecast;
            G.Forecast := Roll_Weather (G.Turn + 1);
            Log ("Turn" & Positive'Image (G.Turn) & ": "
                 & To_String (G.Sides (G.Current).Name));
            if G.Weather /= Was then
               Raise_Event ("weather");
            end if;
            Announce_Weather;
         end;
      else
         Log ("Turn" & Positive'Image (G.Turn) & ": "
              & To_String (G.Sides (G.Current).Name));
      end if;
      Begin_Side_Turn (G.Current);
   end End_Turn;

end Engine.Game;
