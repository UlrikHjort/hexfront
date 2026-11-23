-- ***************************************************************************
--                     Hexfront - Engine.AI
--
--           Copyright (C) 2026 By Ulrik Hørlyk Hjort
--
-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files (the
-- "Software"), to deal in the Software without restriction, including
-- without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to
-- the following conditions:
--
-- The above copyright notice and this permission notice shall be
-- included in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
-- NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
-- LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
-- OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
-- WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
-- ***************************************************************************

with Ada.Containers.Vectors;
with Ada.Numerics.Discrete_Random;
with Engine.Hexes;           use Engine.Hexes;
with Engine.Terrain;         use Engine.Terrain;
with Engine.Units;           use Engine.Units;
with Engine.Game;            use Engine.Game;

package body Engine.AI is

   package Index_Vectors is new Ada.Containers.Vectors (Positive, Positive);
   Queue : Index_Vectors.Vector;
   Next  : Positive := 1;

   subtype Pick is Integer range 0 .. 999;
   package Rand is new Ada.Numerics.Discrete_Random (Pick);
   Gen : Rand.Generator;
   Seeded : Boolean := False;

   -------------
   -- Helpers --
   -------------

   --  All enemy knowledge goes through Known / Remembered so that a
   --  "fair" computer player respects the fog of war.

   function Enemies_Adjacent (H : Hex; Side : Player_Side) return Natural is
      N : Natural := 0;
   begin
      for D in Direction loop
         declare
            U : constant Natural := Unit_At (Neighbor (H, D));
         begin
            if Is_Enemy (U, Side) and then Known (U, Side) then
               N := N + 1;
            end if;
         end;
      end loop;
      return N;
   end Enemies_Adjacent;

   function Enemy_In_Range (H : Hex; Side : Player_Side; Rng : Positive)
                            return Boolean is
   begin
      for I in G.Units.First_Index .. G.Units.Last_Index loop
         declare
            E : constant Unit := G.Units (I);
         begin
            if E.Alive and then E.Side /= Side and then not Is_Air (I)
              and then Remembered (I, Side)
              and then Distance (Believed_Pos (I, Side), H) <= Rng
            then
               return True;
            end if;
         end;
      end loop;
      return False;
   end Enemy_In_Range;

   function Nearest_Base (H : Hex; Side : Player_Side) return Hex is
      Best   : Hex := No_Hex;
      Best_D : Natural := Natural'Last;
   begin
      for C in 0 .. G.Cols - 1 loop
         for R in 0 .. G.Rows - 1 loop
            if G.Cells (C, R).Owner = Side
              and then G.Cells (C, R).Terrain in Airfield | City | Town
              and then Distance ((C, R), H) < Best_D
            then
               Best   := (C, R);
               Best_D := Distance ((C, R), H);
            end if;
         end loop;
      end loop;
      return Best;
   end Nearest_Base;

   --------------
   -- Purchase --
   --------------

   procedure Shop (Side : Player_Side) is
      Reserve : constant Integer := 60;  --  kept for reinforcements
      Bought  : Natural := 0;
   begin
      if not Seeded then
         Rand.Reset (Gen);
         Seeded := True;
      end if;
      while Bought < 3 loop
         declare
            Budget  : constant Integer := G.Sides (Side).Prestige - Reserve;
            Choice  : Natural := 0;
            Best    : Integer := -1;
         begin
            exit when Budget < 100;
            --  Pick an affordable type, favouring pricier (better) ones
            --  with some randomness for variety.
            for T in G.Types.First_Index .. G.Types.Last_Index loop
               if May_Buy (T, Side) and then G.Types (T).Cost <= Budget
                 and then Has_Deploy_Hex (T, Side)
               then
                  declare
                     Score : constant Integer :=
                       G.Types (T).Cost + Rand.Random (Gen) / 3;
                  begin
                     if Score > Best then
                        Best   := Score;
                        Choice := T;
                     end if;
                  end;
               end if;
            end loop;
            exit when Choice = 0;
            --  Deploy as close to the enemy as is allowed.
            declare
               Spot   : Hex := No_Hex;
               Spot_D : Natural := Natural'Last;
            begin
               for C in 0 .. G.Cols - 1 loop
                  for R in 0 .. G.Rows - 1 loop
                     if Can_Deploy (Choice, Side, (C, R)) then
                        if Spot = No_Hex then
                           Spot := (C, R);   --  fallback: any legal hex
                        end if;
                        for I in G.Units.First_Index .. G.Units.Last_Index loop
                           if G.Units (I).Side /= Side
                             and then Remembered (I, Side)
                             and then Distance (Believed_Pos (I, Side), (C, R))
                                      < Spot_D
                           then
                              Spot_D := Distance (Believed_Pos (I, Side),
                                                  (C, R));
                              Spot   := (C, R);
                           end if;
                        end loop;
                     end if;
                  end loop;
               end loop;
               exit when Spot = No_Hex;
               Buy (Choice, Side, Spot);
               Bought := Bought + 1;
            end;
         end;
      end loop;
   end Shop;

   ----------------
   -- Begin_Turn --
   ----------------

   --  The attacker's "main effort": the enemy-held objective that looks
   --  weakest relative to how far our army is from it.
   Main_Effort : Hex := No_Hex;

   procedure Choose_Main_Effort (Side : Player_Side) is
      Best_Score : Float := Float'Last;
      CC, CR     : Float := 0.0;
      N          : Natural := 0;
   begin
      Main_Effort := No_Hex;
      for U of G.Units loop
         if U.Alive and then U.Side = Side then
            CC := CC + Float (U.Pos.Col);
            CR := CR + Float (U.Pos.Row);
            N  := N + 1;
         end if;
      end loop;
      if N = 0 then
         return;
      end if;
      declare
         Centre : constant Hex := (Integer (CC / Float (N)),
                                   Integer (CR / Float (N)));
      begin
         for C in 0 .. G.Cols - 1 loop
            for R in 0 .. G.Rows - 1 loop
               if G.Cells (C, R).Victory and then G.Cells (C, R).Owner /= Side
               then
                  declare
                     Defence : Float := 0.0;
                  begin
                     for I in G.Units.First_Index .. G.Units.Last_Index loop
                        if G.Units (I).Side /= Side
                          and then Remembered (I, Side)
                          and then Distance (Believed_Pos (I, Side), (C, R))
                                   <= 2
                        then
                           Defence := Defence + Float (G.Units (I).Strength);
                        end if;
                     end loop;
                     declare
                        Score : constant Float :=
                          Defence + 2.0 * Float (Distance (Centre, (C, R)));
                     begin
                        if Score < Best_Score then
                           Best_Score  := Score;
                           Main_Effort := (C, R);
                        end if;
                     end;
                  end;
               end if;
            end loop;
         end loop;
      end;
   end Choose_Main_Effort;

   procedure Begin_Turn is
      function Rank (I : Positive) return Natural is
        (case Type_Of (I).Class is
            when Fighter   => 1,    --  clear the skies
            when Artillery => 2,    --  soften the line
            when Bomber    => 3,
            when others    => 4);
   begin
      Shop (G.Current);
      if G.Current = G.Attacker then
         Choose_Main_Effort (G.Current);
      else
         Main_Effort := No_Hex;
      end if;
      Queue.Clear;
      Next := 1;
      for Pass in 1 .. 4 loop
         for I in G.Units.First_Index .. G.Units.Last_Index loop
            if G.Units (I).Alive and then G.Units (I).Side = G.Current
              and then Rank (I) = Pass
            then
               Queue.Append (I);
            end if;
         end loop;
      end loop;
   end Begin_Turn;

   -------------
   -- Scoring --
   -------------

   function Attack_Score
     (A : Unit_Index; From : Hex; D : Unit_Index) return Float
   is
      P  : constant Prediction := Predict (A, From, D);
      AV : constant Float := Float (Type_Of (A).Cost) / 10.0;
      DV : constant Float := Float (Type_Of (D).Cost) / 10.0;
      DU : constant Unit  := Get (D);
      S  : Float := P.Def_Loss * DV - P.Att_Loss * AV;
   begin
      if P.Def_Loss >= Float (DU.Strength) - 0.5 then
         S := S + DV * 2.0;              --  likely kill
      end if;
      if not Is_Air (D) and then G.Cells (DU.Pos.Col, DU.Pos.Row).Victory then
         S := S + 10.0;                  --  clear the objective
      end if;
      if P.Support_Threat then
         S := S - AV * 1.5;
      end if;
      if not Is_Air (D) then
         --  Concentrate: finish what friends have started.
         for Dir in Direction loop
            declare
               F : constant Natural := Unit_At (Neighbor (DU.Pos, Dir));
            begin
               if F /= No_Unit and then F /= A
                 and then G.Units (F).Side = G.Units (A).Side
               then
                  S := S + 1.5;
               end if;
            end;
         end loop;
         if Is_Surrounded (D) then
            S := S + DV;                 --  trapped units are easy prey
         end if;
         --  Defender: anything next to our objectives must be thrown back.
         for Dir in Direction loop
            declare
               N : constant Hex := Neighbor (DU.Pos, Dir);
            begin
               if In_Map (N) and then G.Cells (N.Col, N.Row).Victory
                 and then G.Cells (N.Col, N.Row).Owner = G.Units (A).Side
               then
                  S := S + 6.0;
                  exit;
               end if;
            end;
         end loop;
      end if;
      return S;
   end Attack_Score;

   --  Where should this unit be heading?
   function Goal_For (U : Unit_Index) return Hex is
      Un        : constant Unit := Get (U);
      Best      : Hex := No_Hex;
      Best_Dist : Natural := Natural'Last;
      Attacking : constant Boolean := Un.Side = G.Attacker;
   begin
      if Is_Air (U) then
         --  Aircraft: go where the enemy ground forces are.
         for I in G.Units.First_Index .. G.Units.Last_Index loop
            declare
               E : constant Unit := G.Units (I);
               P : constant Hex := Believed_Pos (I, Un.Side);
            begin
               if E.Alive and then E.Side /= Un.Side and then not Is_Air (I)
                 and then Remembered (I, Un.Side)
                 and then Distance (P, Un.Pos) < Best_Dist
               then
                  Best := P;
                  Best_Dist := Distance (P, Un.Pos);
               end if;
            end;
         end loop;
         if Best = No_Hex then
            --  Nothing known: patrol towards the enemy-held objectives.
            for C in 0 .. G.Cols - 1 loop
               for R in 0 .. G.Rows - 1 loop
                  if G.Cells (C, R).Victory
                    and then G.Cells (C, R).Owner /= Un.Side
                    and then Distance ((C, R), Un.Pos) < Best_Dist
                  then
                     Best := (C, R);
                     Best_Dist := Distance ((C, R), Un.Pos);
                  end if;
               end loop;
            end loop;
         end if;
         return (if Best = No_Hex then Un.Pos else Best);
      end if;

      --  Objectives held by the enemy (attacker: to take; defender: retake)
      for C in 0 .. G.Cols - 1 loop
         for R in 0 .. G.Rows - 1 loop
            if G.Cells (C, R).Victory and then G.Cells (C, R).Owner /= Un.Side
              and then Distance ((C, R), Un.Pos) < Best_Dist
            then
               Best := (C, R);
               Best_Dist := Distance ((C, R), Un.Pos);
            end if;
         end loop;
      end loop;

      if Attacking and then Main_Effort /= No_Hex and then Best_Dist > 5 then
         return Main_Effort;
      end if;

      if not Attacking then
         --  Defender: stay near own objectives unless one has fallen
         --  close by.
         declare
            Own      : Hex := No_Hex;
            Own_Dist : Natural := Natural'Last;
         begin
            for C in 0 .. G.Cols - 1 loop
               for R in 0 .. G.Rows - 1 loop
                  if G.Cells (C, R).Victory
                    and then G.Cells (C, R).Owner = Un.Side
                    and then Distance ((C, R), Un.Pos) < Own_Dist
                  then
                     Own := (C, R);
                     Own_Dist := Distance ((C, R), Un.Pos);
                  end if;
               end loop;
            end loop;
            if Best /= No_Hex and then Best_Dist <= 8 then
               return Best;
            elsif Own /= No_Hex then
               if Own_Dist <= 3 then
                  return Un.Pos;            --  hold the line
               end if;
               return Own;
            end if;
         end;
      end if;

      if Best = No_Hex then
         --  No objectives: hunt the nearest enemy we know of.
         for I in G.Units.First_Index .. G.Units.Last_Index loop
            declare
               P : constant Hex := Believed_Pos (I, Un.Side);
            begin
               if G.Units (I).Alive and then G.Units (I).Side /= Un.Side
                 and then Remembered (I, Un.Side)
                 and then Distance (P, Un.Pos) < Best_Dist
               then
                  Best := P;
                  Best_Dist := Distance (P, Un.Pos);
               end if;
            end;
         end loop;
      end if;
      return (if Best = No_Hex then Un.Pos else Best);
   end Goal_For;

   --  Best attack available from hex From.
   procedure Best_Attack_From
     (A : Unit_Index; From : Hex; Target : out Natural; Score : out Float) is
   begin
      Target := No_Unit;
      Score  := Float'First;
      for D in G.Units.First_Index .. G.Units.Last_Index loop
         if Can_Attack_From (A, From, D) then
            declare
               S : constant Float := Attack_Score (A, From, D);
            begin
               if S > Score then
                  Score  := S;
                  Target := D;
               end if;
            end;
         end if;
      end loop;
   end Best_Attack_From;

   --  Can an aircraft at H (with Fuel_Left) still make it home?
   function Safe_For_Air (U : Unit_Index; H : Hex; Fuel_Left : Integer)
                          return Boolean
   is
      Base : constant Hex := Nearest_Base (H, Get (U).Side);
   begin
      return Base /= No_Hex and then Distance (H, Base) + 5 <= Fuel_Left;
   end Safe_For_Air;

   ---------
   -- Act --
   ---------

   procedure Act (U : Unit_Index) is
      T         : constant Unit_Type := Type_Of (U);
      Side      : constant Player_Side := Get (U).Side;
      Flying    : constant Boolean := Is_Air (T);
      Threshold : constant Float :=
        (if Flying then 2.0 elsif Side = G.Attacker then -2.0 else 1.0);
      Reach     : Reach_Map;
      Target    : Natural;
      Score     : Float;
      Best_Hex  : Hex;
      Best_Tgt  : Natural := No_Unit;
      Best_Sc   : Float := Float'First;
   begin
      --  Worn units rest and refit.
      if Get (U).Strength <= 4 and then Can_Reinforce (U) then
         Reinforce (U);
         return;
      end if;

      --  Battered units in contact pull back instead of dying in place
      --  (unless they are holding an objective).
      if not Flying and then T.Mover /= Static
        and then Get (U).Strength <= 3 and then Get (U).Moves_Left > 0
        and then Enemy_In_Range (Get (U).Pos, Side, 2)
        and then not (G.Cells (Get (U).Pos.Col, Get (U).Pos.Row).Victory
                      and then G.Cells (Get (U).Pos.Col, Get (U).Pos.Row).Owner
                               = Side)
      then
         declare
            R    : Reach_Map;
            Here : constant Hex := Get (U).Pos;
            Best : Hex := Here;

            function Threat (H : Hex) return Float is
               N : Float := 0.0;
            begin
               for I in G.Units.First_Index .. G.Units.Last_Index loop
                  if G.Units (I).Side /= Side and then Remembered (I, Side)
                    and then not Is_Air (I)
                  then
                     case Distance (Believed_Pos (I, Side), H) is
                        when 0 .. 1 => N := N + 3.0;
                        when 2      => N := N + 1.5;
                        when 3      => N := N + 0.5;
                        when others => null;
                     end case;
                  end if;
               end loop;
               if G.Cells (H.Col, H.Row).Owner = Side
                 and then Is_Capturable (Terrain_At (H))
               then
                  N := N - 1.0;          --  friendly town: refit there
               end if;
               return N;
            end Threat;

            Best_T : Float := Threat (Here);
         begin
            Compute_Reach (U, R);
            for C in 0 .. G.Cols - 1 loop
               for Rw in 0 .. G.Rows - 1 loop
                  if Can_Move_To (U, R, (C, Rw))
                    and then Threat ((C, Rw)) < Best_T - 0.4
                  then
                     Best_T := Threat ((C, Rw));
                     Best   := (C, Rw);
                  end if;
               end loop;
            end loop;
            if Best /= Here then
               Log (Unit_Name (U) & " withdraws to regroup");
               Move_Unit (U, Best, R);
               return;
            end if;
         end;
      end if;
      if (Get (U).Ammo = 0
          or else (T.Max_Fuel > 0
                   and then Get (U).Fuel < (if Flying then T.Max_Fuel / 2
                                            else T.Movement)))
        and then Can_Resupply (U)
      then
         Resupply (U);
         return;
      end if;

      Compute_Reach (U, Reach);

      --  Aircraft low on fuel or ammo head home.
      if Flying and then (Get (U).Ammo = 0
                          or else not Safe_For_Air (U, Get (U).Pos,
                                                    Get (U).Fuel - 4))
      then
         declare
            Base : constant Hex := Nearest_Base (Get (U).Pos, Side);
            Best : Hex := No_Hex;
            Best_D : Natural := Natural'Last;
         begin
            if Base /= No_Hex then
               for C in 0 .. G.Cols - 1 loop
                  for R in 0 .. G.Rows - 1 loop
                     if Can_Move_To (U, Reach, (C, R))
                       and then Distance ((C, R), Base) < Best_D
                     then
                        Best := (C, R);
                        Best_D := Distance ((C, R), Base);
                     end if;
                  end loop;
               end loop;
               if Best /= No_Hex
                 and then Best_D < Distance (Get (U).Pos, Base)
               then
                  Move_Unit (U, Best, Reach);
               end if;
            end if;
            return;
         end;
      end if;

      --  1. Attack options: from here, or after a move.
      Best_Attack_From (U, Get (U).Pos, Best_Tgt, Best_Sc);
      Best_Hex := Get (U).Pos;
      if Best_Sc > Float'First then
         Best_Sc := Best_Sc + 1.0;           --  prefer not moving
      end if;

      if T.Class /= Artillery then
         for C in 0 .. G.Cols - 1 loop
            for R in 0 .. G.Rows - 1 loop
               if Can_Move_To (U, Reach, (C, R))
                 and then (not Flying
                           or else Safe_For_Air
                             (U, (C, R),
                              Get (U).Fuel - Reach.Cost (C, R)))
               then
                  Best_Attack_From (U, (C, R), Target, Score);
                  if Target /= No_Unit then
                     if not Flying then
                        Score := Score
                          + 0.5 * Float (Defense_Bonus (Terrain_At ((C, R))));
                     end if;
                     if Score > Best_Sc then
                        Best_Sc  := Score;
                        Best_Tgt := Target;
                        Best_Hex := (C, R);
                     end if;
                  end if;
               end if;
            end loop;
         end loop;
      end if;

      if Best_Tgt /= No_Unit and then Best_Sc > Threshold then
         if Best_Hex /= Get (U).Pos then
            Move_Unit (U, Best_Hex, Reach);
         end if;
         if Get (U).Alive and then Can_Attack (U, Best_Tgt) then
            Attack (U, Best_Tgt);
         end if;
         return;
      end if;

      --  2. Manoeuvre towards the goal.
      declare
         Goal     : constant Hex := Goal_For (U);
         Here     : constant Hex := Get (U).Pos;
         Best     : Hex := Here;
         Best_Val : Float;
         Weak     : constant Boolean :=
           T.Class in Artillery | Anti_Air or else Get (U).Strength <= 4;

         function Value_Of (H : Hex) return Float is
            V : Float := -3.0 * Float (Distance (H, Goal));
         begin
            if Flying then
               --  Hover a little behind the front, never out of fuel.
               if not Safe_For_Air (U, H, Get (U).Fuel - Reach.Cost
                                    (H.Col, H.Row))
               then
                  return -10_000.0;
               end if;
               return V - (if Distance (H, Goal) < 2 then 8.0 else 0.0);
            end if;
            V := V + 0.7 * Float (Defense_Bonus (Terrain_At (H)));
            --  Stay within reach of the supply lines.
            if T.Mover not in Static | Naval then
               case Supply_At (H, Side) is
                  when Supplied   => null;
                  when Low_Supply => V := V - 1.0;
                  when Cut_Off    => V := V - 10.0;
               end case;
            end if;
            if Weak then
               V := V - 6.0 * Float (Enemies_Adjacent (H, Side));
            end if;
            if T.Class = Artillery
              and then Enemy_In_Range (H, Side, T.Max_Range)
              and then Enemies_Adjacent (H, Side) = 0
            then
               V := V + 8.0;
            end if;
            if G.Cells (H.Col, H.Row).Victory
              and then G.Cells (H.Col, H.Row).Owner /= Side
            then
               V := V + 25.0;
            end if;
            --  Envelopment: close the ring around enemies that friends
            --  are already pressing.
            if not Weak then
               for Dir in Direction loop
                  declare
                     E : constant Natural := Unit_At (Neighbor (H, Dir));
                  begin
                     if E /= No_Unit and then Is_Enemy (E, Side)
                       and then Known (E, Side)
                     then
                        declare
                           Friends : Natural := 0;
                        begin
                           for D2 in Direction loop
                              declare
                                 F : constant Natural :=
                                   Unit_At (Neighbor (G.Units (E).Pos, D2));
                              begin
                                 if F /= No_Unit and then F /= U
                                   and then G.Units (F).Side = Side
                                 then
                                    Friends := Friends + 1;
                                 end if;
                              end;
                           end loop;
                           if Friends >= 2 then
                              V := V + 2.5 * Float (Friends);
                           end if;
                        end;
                     end if;
                  end;
               end loop;
            end if;
            return V;
         end Value_Of;
      begin
         --  Staying put also earns entrenchment. A captured objective
         --  with enemies nearby must be held, not abandoned.
         Best_Val := Value_Of (Here) + 1.5;
         if not Flying and then G.Cells (Here.Col, Here.Row).Victory
           and then G.Cells (Here.Col, Here.Row).Owner = Side
           and then Enemy_In_Range (Here, Side, 3)
         then
            Best_Val := Float'Last;
         end if;
         for C in 0 .. G.Cols - 1 loop
            for R in 0 .. G.Rows - 1 loop
               if Can_Move_To (U, Reach, (C, R)) then
                  declare
                     V : constant Float := Value_Of ((C, R));
                  begin
                     if V > Best_Val then
                        Best_Val := V;
                        Best := (C, R);
                     end if;
                  end;
               end if;
            end loop;
         end loop;

         if Best /= Here then
            Move_Unit (U, Best, Reach);
            --  Opportunistic attack after the move.
            if Get (U).Alive then
               Best_Attack_From (U, Get (U).Pos, Target, Score);
               if Target /= No_Unit and then Score > Threshold then
                  Attack (U, Target);
               end if;
            end if;
         elsif Can_Resupply (U) then
            Resupply (U);
         end if;
      end;
   end Act;

   ----------
   -- Step --
   ----------

   function Step return Boolean is
   begin
      while Next <= Natural (Queue.Length) loop
         declare
            U : constant Positive := Queue (Next);
         begin
            Next := Next + 1;
            if G.Winner /= 0 then
               return False;
            end if;
            if Get (U).Alive then
               Act (U);
               return True;
            end if;
         end;
      end loop;
      return False;
   end Step;

end Engine.AI;
