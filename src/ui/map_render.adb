with Ada.Numerics;                 use Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Ada.Strings.Unbounded;        use Ada.Strings.Unbounded;
with Engine;                       use Engine;
with Engine.Terrain;               use Engine.Terrain;
with Engine.Units;                 use Engine.Units;
with Anim;

package body Map_Render is

   use Cairo;
   package EF renames Ada.Numerics.Elementary_Functions;

   Sqrt3 : constant Gdouble := 1.732_050_807_57;
   Hex_H : constant Gdouble := Sqrt3 * Radius;

   function Center_X (H : Hex) return Gdouble is
     (Margin + Radius + Gdouble (H.Col) * 1.5 * Radius);

   function Center_Y (H : Hex) return Gdouble is
     (Margin + Hex_H / 2.0 + Gdouble (H.Row) * Hex_H
      + (if H.Col mod 2 = 1 then Hex_H / 2.0 else 0.0));

   procedure Map_Size (Width, Height : out Gint) is
   begin
      Width  := Gint (Zoom * (2.0 * Margin + Radius * 2.0
                      + Gdouble (Integer'Max (G.Cols - 1, 0)) * 1.5 * Radius));
      Height := Gint (Zoom * (2.0 * Margin
                              + Hex_H * (Gdouble (G.Rows) + 0.5)));
   end Map_Size;

   function Hex_At (SX, SY : Gdouble) return Hex is
      X : constant Gdouble := SX / Zoom;
      Y : constant Gdouble := SY / Zoom;
      Approx : constant Integer :=
        Integer (Gdouble'Floor ((X - Margin - Radius) / (1.5 * Radius) + 0.5));
      Best   : Hex := No_Hex;
      Best_D : Gdouble := Gdouble'Last;
   begin
      for C in Approx - 1 .. Approx + 1 loop
         declare
            R0 : constant Integer :=
              Integer (Gdouble'Floor ((Y - Margin) / Hex_H));
         begin
            for R in R0 - 1 .. R0 + 1 loop
               declare
                  H  : constant Hex := (C, R);
                  DX : constant Gdouble := X - Center_X (H);
                  DY : constant Gdouble := Y - Center_Y (H);
                  D  : constant Gdouble := DX * DX + DY * DY;
               begin
                  if In_Map (H) and then D < Best_D then
                     Best_D := D;
                     Best   := H;
                  end if;
               end;
            end loop;
         end;
      end loop;
      if Best_D > Radius * Radius then
         return No_Hex;
      end if;
      return Best;
   end Hex_At;

   ---------------
   -- Utilities --
   ---------------

   procedure Color (Cr : Cairo_Context; R, G, B : Gdouble;
                    A : Gdouble := 1.0) is
   begin
      Set_Source_Rgba (Cr, R, G, B, A);
   end Color;

   procedure Hex_Path (Cr : Cairo_Context; CX, CY : Gdouble;
                       Scale : Gdouble := 1.0) is
   begin
      for I in 0 .. 5 loop
         declare
            A  : constant Float := Float (I) * Pi / 3.0;
            PX : constant Gdouble :=
              CX + Radius * Scale * Gdouble (EF.Cos (A));
            PY : constant Gdouble :=
              CY + Radius * Scale * Gdouble (EF.Sin (A));
         begin
            if I = 0 then
               Move_To (Cr, PX, PY);
            else
               Line_To (Cr, PX, PY);
            end if;
         end;
      end loop;
      Close_Path (Cr);
   end Hex_Path;

   procedure Text_Centered (Cr : Cairo_Context; X, Y : Gdouble; S : String;
                            Size : Gdouble; Bold : Boolean := False) is
   begin
      Select_Font_Face (Cr, "Sans", Cairo_Font_Slant_Normal,
                        (if Bold then Cairo_Font_Weight_Bold
                         else Cairo_Font_Weight_Normal));
      Set_Font_Size (Cr, Size);
      --  Approximate centering; good enough for short labels.
      Move_To (Cr, X - Gdouble (S'Length) * Size * 0.29, Y);
      Show_Text (Cr, S);
   end Text_Centered;

   type Shade is record
      R, G, B : Gdouble;
   end record;

   function Terrain_Color (T : Terrain_Kind) return Shade is
   begin
      case T is
         when Clear    => return (0.78, 0.84, 0.56);
         when Road     => return (0.80, 0.84, 0.58);
         when Forest   => return (0.42, 0.60, 0.33);
         when Hills    => return (0.72, 0.68, 0.45);
         when Mountain => return (0.58, 0.53, 0.47);
         when River    => return (0.74, 0.82, 0.62);
         when Swamp    => return (0.55, 0.65, 0.52);
         when Town     => return (0.80, 0.80, 0.66);
         when City     => return (0.74, 0.72, 0.66);
         when Fortress => return (0.66, 0.64, 0.60);
         when Water    => return (0.36, 0.55, 0.78);
         when Trench   => return (0.66, 0.58, 0.42);
         when Airfield => return (0.76, 0.80, 0.60);
      end case;
   end Terrain_Color;

   function Is_Road_Like (T : Terrain_Kind) return Boolean is
     (T in Road | Town | City | Fortress | Airfield);

   --  Connect hex centre to neighbours satisfying a property.
   procedure Draw_Links
     (Cr : Cairo_Context; H : Hex; Width : Gdouble;
      Wants : not null access function (T : Terrain_Kind) return Boolean)
   is
      CX : constant Gdouble := Center_X (H);
      CY : constant Gdouble := Center_Y (H);
      Any : Boolean := False;
   begin
      Set_Line_Width (Cr, Width);
      Set_Line_Cap (Cr, Cairo_Line_Cap_Round);
      for D in Direction loop
         declare
            N : constant Hex := Neighbor (H, D);
         begin
            if In_Map (N) and then Wants (Terrain_At (N)) then
               Move_To (Cr, CX, CY);
               Line_To (Cr, (CX + Center_X (N)) / 2.0,
                        (CY + Center_Y (N)) / 2.0);
               Any := True;
            end if;
         end;
      end loop;
      if not Any then
         Move_To (Cr, CX - 6.0, CY);
         Line_To (Cr, CX + 6.0, CY);
      end if;
      Stroke (Cr);
   end Draw_Links;

   function Watery (T : Terrain_Kind) return Boolean is
     (T in River | Water | Town | City | Fortress | Airfield);

   function Is_River (T : Terrain_Kind) return Boolean is (T = River);

   function River_Neighbors (H : Hex) return Natural is
      N : Natural := 0;
   begin
      for D in Direction loop
         if In_Map (Neighbor (H, D))
           and then Terrain_At (Neighbor (H, D)) = River
         then
            N := N + 1;
         end if;
      end loop;
      return N;
   end River_Neighbors;

   procedure Decorate (Cr : Cairo_Context; H : Hex; T : Terrain_Kind) is
      CX : constant Gdouble := Center_X (H);
      CY : constant Gdouble := Center_Y (H);
   begin
      case T is
         when Forest =>
            Color (Cr, 0.20, 0.40, 0.18);
            for P of Dash_Array'(-10.0, 0.0, 10.0) loop
               Arc (Cr, CX + P, CY - 4.0 + abs (P) * 0.5, 6.0, 0.0, 2.0 * Pi);
               Fill (Cr);
            end loop;
            Arc (Cr, CX - 4.0, CY + 9.0, 5.0, 0.0, 2.0 * Pi);
            Fill (Cr);
            Arc (Cr, CX + 7.0, CY + 10.0, 5.0, 0.0, 2.0 * Pi);
            Fill (Cr);
         when Hills =>
            Color (Cr, 0.50, 0.44, 0.26);
            Set_Line_Width (Cr, 2.0);
            Arc (Cr, CX - 6.0, CY + 6.0, 9.0, Pi, 2.0 * Pi);
            Stroke (Cr);
            Arc (Cr, CX + 8.0, CY + 2.0, 7.0, Pi, 2.0 * Pi);
            Stroke (Cr);
         when Mountain =>
            Color (Cr, 0.38, 0.34, 0.30);
            Move_To (Cr, CX - 16.0, CY + 10.0);
            Line_To (Cr, CX - 4.0, CY - 12.0);
            Line_To (Cr, CX + 4.0, CY);
            Line_To (Cr, CX + 9.0, CY - 7.0);
            Line_To (Cr, CX + 17.0, CY + 10.0);
            Close_Path (Cr);
            Fill (Cr);
            Color (Cr, 0.95, 0.95, 0.95);
            Move_To (Cr, CX - 7.0, CY - 7.0);
            Line_To (Cr, CX - 4.0, CY - 12.0);
            Line_To (Cr, CX - 1.0, CY - 7.0);
            Close_Path (Cr);
            Fill (Cr);
         when River =>
            Color (Cr, 0.25, 0.45, 0.80);
            Draw_Links (Cr, H, 6.0, Watery'Access);
         when Swamp =>
            Color (Cr, 0.25, 0.45, 0.65);
            Set_Line_Width (Cr, 1.5);
            for I in -1 .. 1 loop
               Move_To (Cr, CX - 12.0 + Gdouble (I) * 4.0,
                        CY + Gdouble (I) * 9.0);
               Line_To (Cr, CX + 8.0 + Gdouble (I) * 4.0,
                        CY + Gdouble (I) * 9.0);
            end loop;
            Stroke (Cr);
            Color (Cr, 0.30, 0.45, 0.25);
            for I in -1 .. 1 loop
               Move_To (Cr, CX + Gdouble (I) * 9.0, CY + 4.0);
               Line_To (Cr, CX + Gdouble (I) * 9.0 + 2.0, CY - 6.0);
            end loop;
            Stroke (Cr);
         when Airfield =>
            Color (Cr, 0.45, 0.45, 0.45);
            Save (Cr);
            Translate (Cr, CX, CY);
            Rotate (Cr, -0.5);
            Rectangle (Cr, -20.0, -4.0, 40.0, 8.0);
            Fill (Cr);
            Color (Cr, 0.95, 0.95, 0.95);
            Set_Line_Width (Cr, 1.0);
            Set_Dash (Cr, (3.0, 3.0), 0.0);
            Move_To (Cr, -17.0, 0.0);
            Line_To (Cr, 17.0, 0.0);
            Stroke (Cr);
            Set_Dash (Cr, (1 .. 0 => 0.0), 0.0);
            Restore (Cr);
            Color (Cr, 0.40, 0.35, 0.30);
            Rectangle (Cr, CX + 6.0, CY + 8.0, 9.0, 6.0);
            Fill (Cr);
         when Road | Town | City | Fortress =>
            if T /= Road and then River_Neighbors (H) > 0 then
               Color (Cr, 0.25, 0.45, 0.80);
               Draw_Links (Cr, H, 6.0, Is_River'Access);
            end if;
            Color (Cr, 0.55, 0.45, 0.32);
            Draw_Links (Cr, H, 4.0, Is_Road_Like'Access);
            if T = Town then
               Color (Cr, 0.55, 0.30, 0.25);
               Rectangle (Cr, CX - 11.0, CY - 9.0, 8.0, 7.0);
               Rectangle (Cr, CX + 3.0, CY - 10.0, 8.0, 8.0);
               Rectangle (Cr, CX - 4.0, CY + 2.0, 9.0, 7.0);
               Fill (Cr);
            elsif T = City then
               Color (Cr, 0.45, 0.42, 0.42);
               for I in -1 .. 1 loop
                  for J in -1 .. 1 loop
                     if (I + J) mod 2 = 0 then
                        Rectangle (Cr, CX + Gdouble (I) * 9.0 - 4.0,
                                   CY + Gdouble (J) * 8.0 - 4.0, 8.0, 7.0);
                     end if;
                  end loop;
               end loop;
               Fill (Cr);
            elsif T = Fortress then
               Color (Cr, 0.35, 0.33, 0.32);
               Set_Line_Width (Cr, 3.0);
               Hex_Path (Cr, CX, CY, 0.45);
               Stroke (Cr);
            end if;
         when Trench =>
            Color (Cr, 0.35, 0.25, 0.15);
            Set_Line_Width (Cr, 2.5);
            Move_To (Cr, CX - 2.0, CY - 22.0);
            for I in 1 .. 6 loop
               Line_To (Cr, CX + (if I mod 2 = 0 then -4.0 else 4.0),
                        CY - 22.0 + Gdouble (I) * 7.3);
            end loop;
            Stroke (Cr);
         when Clear | Water =>
            null;
      end case;
   end Decorate;

   -------------------
   -- Unit counters --
   -------------------

   procedure Draw_Symbol (Cr : Cairo_Context; C : Unit_Class;
                          X, Y, W, H : Gdouble) is
   begin
      Set_Line_Width (Cr, 1.4);
      Color (Cr, 0.1, 0.1, 0.1);
      case C is
         when Infantry =>
            Move_To (Cr, X, Y);
            Line_To (Cr, X + W, Y + H);
            Move_To (Cr, X + W, Y);
            Line_To (Cr, X, Y + H);
            Stroke (Cr);
         when Cavalry =>
            Move_To (Cr, X, Y + H);
            Line_To (Cr, X + W, Y);
            Stroke (Cr);
         when Recon =>
            Move_To (Cr, X, Y + H);
            Line_To (Cr, X + W, Y);
            Stroke (Cr);
            Save (Cr);
            Translate (Cr, X + W / 2.0, Y + H / 2.0);
            Scale (Cr, W * 0.30, H * 0.30);
            Arc (Cr, 0.0, 0.0, 1.0, 0.0, 2.0 * Pi);
            Restore (Cr);
            Stroke (Cr);
         when Armor =>
            Save (Cr);
            Translate (Cr, X + W / 2.0, Y + H / 2.0);
            Scale (Cr, W * 0.36, H * 0.30);
            Arc (Cr, 0.0, 0.0, 1.0, 0.0, 2.0 * Pi);
            Restore (Cr);
            Stroke (Cr);
         when Artillery =>
            Arc (Cr, X + W / 2.0, Y + H / 2.0, H * 0.22, 0.0, 2.0 * Pi);
            Fill (Cr);
         when Anti_Tank =>
            Move_To (Cr, X, Y + H);
            Line_To (Cr, X + W / 2.0, Y);
            Line_To (Cr, X + W, Y + H);
            Stroke (Cr);
         when Engineer =>
            Move_To (Cr, X + W * 0.2, Y + H * 0.7);
            Line_To (Cr, X + W * 0.2, Y + H * 0.35);
            Line_To (Cr, X + W * 0.8, Y + H * 0.35);
            Line_To (Cr, X + W * 0.8, Y + H * 0.7);
            Move_To (Cr, X + W * 0.5, Y + H * 0.35);
            Line_To (Cr, X + W * 0.5, Y + H * 0.7);
            Stroke (Cr);
         when Anti_Air =>
            Arc (Cr, X + W / 2.0, Y + H, H * 0.75, Pi, 2.0 * Pi);
            Stroke (Cr);
         when Fighter | Bomber =>
            --  Aircraft seen from above, nose to the right.
            Move_To (Cr, X + W * 0.12, Y + H / 2.0);
            Line_To (Cr, X + W * 0.88, Y + H / 2.0);
            Move_To (Cr, X + W * 0.15, Y + H * 0.25);
            Line_To (Cr, X + W * 0.15, Y + H * 0.75);
            Stroke (Cr);
            Move_To (Cr, X + W * 0.55, Y + H * 0.05);
            Line_To (Cr, X + W * (if C = Bomber then 0.40 else 0.48),
                     Y + H * 0.05);
            Line_To (Cr, X + W * (if C = Bomber then 0.40 else 0.48),
                     Y + H * 0.95);
            Line_To (Cr, X + W * 0.55, Y + H * 0.95);
            Close_Path (Cr);
            if C = Bomber then
               Fill (Cr);
            else
               Stroke (Cr);
            end if;
         when Fortification =>
            Set_Line_Width (Cr, 1.2);
            for I in 0 .. 3 loop
               Rectangle (Cr, X + W * (0.1 + 0.22 * Gdouble (I)), Y + 1.0,
                          W * 0.12, H * 0.3);
            end loop;
            Fill (Cr);
            Rectangle (Cr, X + 2.0, Y + H * 0.4, W - 4.0, H * 0.45);
            Stroke (Cr);
      end case;
   end Draw_Symbol;

   function Img (N : Integer) return String is
      S : constant String := Integer'Image (N);
   begin
      return S (S'First + 1 .. S'Last);
   end Img;

   procedure Draw_Unit (Cr : Cairo_Context; U : Unit_Index) is
      Un   : constant Unit      := Get (U);
      T    : constant Unit_Type := Type_Of (U);
      Fly  : constant Boolean   := Is_Air (T);
      Side : constant RGB       := G.Sides (Un.Side).Color;
      AX, AY : Gdouble;
      Moving : constant Boolean := Anim.Override (U, AX, AY);
      --  Aircraft sit in the upper right corner of the hex.
      CX   : constant Gdouble   :=
        (if Moving then AX else Center_X (Un.Pos))
        + (if Fly then 10.0 else 0.0);
      CY   : constant Gdouble   :=
        (if Moving then AY else Center_Y (Un.Pos))
        - (if Fly then 13.0 else 0.0);
      W    : constant Gdouble   := (if Fly then 34.0 else 38.0);
      H    : constant Gdouble   := (if Fly then 26.0 else 30.0);
      X0   : constant Gdouble   := CX - W / 2.0;
      Y0   : constant Gdouble   := CY - H / 2.0 - 2.0;
      Spent : constant Boolean  :=
        Un.Side = G.Current and then Un.Has_Attacked
        and then Un.Moves_Left = 0;
   begin
      --  Shadow
      Color (Cr, 0.0, 0.0, 0.0, 0.35);
      Rectangle (Cr, X0 + 2.0, Y0 + 2.0, W, H);
      Fill (Cr);
      --  Body
      Color (Cr, Gdouble (Side.R), Gdouble (Side.G), Gdouble (Side.B));
      Rectangle (Cr, X0, Y0, W, H);
      Fill_Preserve (Cr);
      Color (Cr, 0.1, 0.1, 0.1);
      Set_Line_Width (Cr, 1.0);
      Stroke (Cr);
      if Fly then
         Color (Cr, 0.55, 0.75, 0.95);
         Rectangle (Cr, X0 + 0.5, Y0 + 0.5, W - 1.0, 2.5);
         Fill (Cr);
      end if;
      --  Symbol box
      Color (Cr, 0.95, 0.94, 0.88);
      Rectangle (Cr, X0 + 7.0, Y0 + 3.0, W - 14.0, 13.0);
      Fill_Preserve (Cr);
      Color (Cr, 0.1, 0.1, 0.1);
      Set_Line_Width (Cr, 1.0);
      Stroke (Cr);
      Draw_Symbol (Cr, T.Class, X0 + 7.0, Y0 + 3.0, W - 14.0, 13.0);
      --  Strength (dark text on light counters)
      if 0.3 * Side.R + 0.59 * Side.G + 0.11 * Side.B > 0.62 then
         Color (Cr, 0.1, 0.1, 0.1);
      else
         Color (Cr, 1.0, 1.0, 1.0);
      end if;
      Text_Centered (Cr, CX, Y0 + H - 3.0, Img (Un.Strength), 10.0, True);
      --  Experience pips
      for I in 1 .. Exp_Level (Un) loop
         Color (Cr, 1.0, 0.85, 0.2);
         Arc (Cr, X0 + 3.0, Y0 + H + 1.0 - Gdouble (I) * 5.0, 1.8,
              0.0, 2.0 * Pi);
         Fill (Cr);
      end loop;
      --  Entrenchment ticks
      for I in 1 .. Natural'Min (Un.Entrench, 6) loop
         Color (Cr, 0.25, 0.18, 0.1);
         Rectangle (Cr, X0 + W - 5.0, Y0 + H - Gdouble (I) * 4.5, 3.0, 3.0);
         Fill (Cr);
      end loop;
      --  Low supply warning
      if Un.Ammo = 0 or else (T.Max_Fuel > 0 and then Un.Fuel < T.Movement)
      then
         Color (Cr, 1.0, 0.3, 0.1);
         Arc (Cr, X0 + W, Y0, 3.5, 0.0, 2.0 * Pi);
         Fill (Cr);
      end if;
      if Spent then
         Color (Cr, 0.0, 0.0, 0.0, 0.35);
         Rectangle (Cr, X0, Y0, W, H);
         Fill (Cr);
      end if;
      if Is_Surrounded (U) then
         Color (Cr, 0.9, 0.05, 0.05);
         Set_Line_Width (Cr, 2.5);
         Rectangle (Cr, X0 - 2.0, Y0 - 2.0, W + 4.0, H + 4.0);
         Stroke (Cr);
      end if;
   end Draw_Unit;

   ----------
   -- Draw --
   ----------

   procedure Draw (Cr : Cairo_Context; V : View_State) is
      Sel_Own : constant Boolean :=
        V.Selected /= 0 and then Get (V.Selected).Alive
        and then Get (V.Selected).Side = G.Current;

      function Shown (U : Unit_Index) return Boolean is
        (Get (U).Alive
         and then (V.Viewer = 0 or else Visible (U, V.Viewer)));
   begin
      Color (Cr, 0.20, 0.22, 0.20);
      Paint (Cr);
      if not G.Loaded then
         return;
      end if;
      Scale (Cr, Zoom, Zoom);

      --  Terrain
      for C in 0 .. G.Cols - 1 loop
         for R in 0 .. G.Rows - 1 loop
            declare
               H  : constant Hex := (C, R);
               T  : constant Terrain_Kind := Terrain_At (H);
               S  : constant Shade := Terrain_Color (T);
            begin
               Hex_Path (Cr, Center_X (H), Center_Y (H));
               Color (Cr, S.R, S.G, S.B);
               Fill (Cr);
               Decorate (Cr, H, T);
            end;
         end loop;
      end loop;

      --  Grid, ownership and names
      for C in 0 .. G.Cols - 1 loop
         for R in 0 .. G.Rows - 1 loop
            declare
               H  : constant Hex := (C, R);
               CX : constant Gdouble := Center_X (H);
               CY : constant Gdouble := Center_Y (H);
               Ce : constant Cell := G.Cells (C, R);
            begin
               Hex_Path (Cr, CX, CY);
               Color (Cr, 0.0, 0.0, 0.0, 0.18);
               Set_Line_Width (Cr, 1.0);
               Stroke (Cr);

               if Ce.Owner /= 0
                 and then (Is_Capturable (Ce.Terrain) or else Ce.Victory)
               then
                  declare
                     O : constant RGB := G.Sides (Ce.Owner).Color;
                  begin
                     --  Little flag in the upper part of the hex.
                     Color (Cr, 0.15, 0.15, 0.15);
                     Set_Line_Width (Cr, 1.2);
                     Move_To (Cr, CX - 14.0, CY - 8.0);
                     Line_To (Cr, CX - 14.0, CY - 22.0);
                     Stroke (Cr);
                     Color (Cr, Gdouble (O.R), Gdouble (O.G), Gdouble (O.B));
                     Rectangle (Cr, CX - 14.0, CY - 22.0, 11.0, 7.0);
                     Fill_Preserve (Cr);
                     Color (Cr, 0.1, 0.1, 0.1);
                     Set_Line_Width (Cr, 0.8);
                     Stroke (Cr);
                  end;
               end if;
               if Ce.Victory then
                  Color (Cr, 1.0, 0.85, 0.1);
                  Set_Line_Width (Cr, 2.5);
                  Hex_Path (Cr, CX, CY, 0.92);
                  Stroke (Cr);
               end if;
               if Length (Ce.Name) > 0 then
                  Color (Cr, 0.0, 0.0, 0.0, 0.8);
                  Text_Centered (Cr, CX, CY + 23.0, To_String (Ce.Name),
                                 8.5, True);
               end if;
            end;
         end loop;
      end loop;

      --  Movement range: darken what cannot be reached.
      if Sel_Own and then V.Show_Reach then
         for C in 0 .. G.Cols - 1 loop
            for R in 0 .. G.Rows - 1 loop
               if V.Reach.Cost (C, R) < 0 then
                  Hex_Path (Cr, Center_X ((C, R)), Center_Y ((C, R)));
                  Color (Cr, 0.0, 0.0, 0.0, 0.30);
                  Fill (Cr);
               end if;
            end loop;
         end loop;
      end if;

      --  Fog of war
      if V.Viewer /= 0 and then G.Fog then
         for C in 0 .. G.Cols - 1 loop
            for R in 0 .. G.Rows - 1 loop
               if not G.Seen (V.Viewer) (C, R) then
                  Hex_Path (Cr, Center_X ((C, R)), Center_Y ((C, R)));
                  Color (Cr, 0.62, 0.62, 0.68, 0.42);
                  Fill (Cr);
               end if;
            end loop;
         end loop;
      end if;

      --  Deployment hexes for a purchase
      if V.Deploy_Type /= 0 then
         for C in 0 .. G.Cols - 1 loop
            for R in 0 .. G.Rows - 1 loop
               if Can_Deploy (V.Deploy_Type, G.Current, (C, R)) then
                  Hex_Path (Cr, Center_X ((C, R)), Center_Y ((C, R)), 0.9);
                  Color (Cr, 0.1, 0.85, 0.2);
                  Set_Line_Width (Cr, 3.0);
                  Stroke (Cr);
               end if;
            end loop;
         end loop;
      end if;

      --  Units: ground first, aircraft on top
      for Pass in Boolean loop
         for I in G.Units.First_Index .. G.Units.Last_Index loop
            if Shown (I) and then Is_Air (I) = Pass then
               Draw_Unit (Cr, I);
            end if;
         end loop;
      end loop;

      --  Attack targets
      if Sel_Own then
         for I in G.Units.First_Index .. G.Units.Last_Index loop
            if Can_Attack (V.Selected, I) and then Shown (I) then
               declare
                  P : constant Hex := Get (I).Pos;
               begin
                  Hex_Path (Cr, Center_X (P), Center_Y (P), 0.95);
                  Color (Cr, 0.9, 0.1, 0.1);
                  Set_Line_Width (Cr, 3.0);
                  Stroke (Cr);
               end;
            end if;
         end loop;
      end if;

      if V.Last_Fight /= No_Hex and then In_Map (V.Last_Fight) then
         Hex_Path (Cr, Center_X (V.Last_Fight), Center_Y (V.Last_Fight),
                   0.8);
         Color (Cr, 1.0, 0.45, 0.0);
         Set_Line_Width (Cr, 3.0);
         Set_Dash (Cr, (4.0, 3.0), 0.0);
         Stroke (Cr);
         Set_Dash (Cr, (1 .. 0 => 0.0), 0.0);
      end if;

      if V.Selected /= 0 and then Get (V.Selected).Alive then
         declare
            P : constant Hex := Get (V.Selected).Pos;
         begin
            Hex_Path (Cr, Center_X (P), Center_Y (P), 0.95);
            Color (Cr, 1.0, 0.95, 0.2);
            Set_Line_Width (Cr, 3.0);
            Stroke (Cr);
         end;
      end if;

      if V.Hover /= No_Hex and then In_Map (V.Hover) then
         Hex_Path (Cr, Center_X (V.Hover), Center_Y (V.Hover));
         Color (Cr, 1.0, 1.0, 1.0, 0.8);
         Set_Line_Width (Cr, 2.0);
         Stroke (Cr);
      end if;

      Anim.Draw_Overlay (Cr);
   end Draw;

   ------------------
   -- Draw_Preview --
   ------------------

   procedure Draw_Preview (Cr : Cairo_Context;
                           P  : Engine.Loader.Preview_Data;
                           W, H : Gdouble)
   is
      function Parse (S : String) return Shade is
         C1, C2 : Natural := 0;
      begin
         for I in S'Range loop
            if S (I) = ',' then
               if C1 = 0 then
                  C1 := I;
               else
                  C2 := I;
               end if;
            end if;
         end loop;
         if C1 = 0 or else C2 = 0 then
            return (0.5, 0.5, 0.5);
         end if;
         return (Gdouble (Integer'Value (S (S'First .. C1 - 1))) / 255.0,
                 Gdouble (Integer'Value (S (C1 + 1 .. C2 - 1))) / 255.0,
                 Gdouble (Integer'Value (S (C2 + 1 .. S'Last))) / 255.0);
      exception
         when Constraint_Error =>
            return (0.5, 0.5, 0.5);
      end Parse;

      R, OX, OY : Gdouble;
   begin
      Color (Cr, 0.20, 0.22, 0.20);
      Paint (Cr);
      if not P.Ok then
         Color (Cr, 0.8, 0.8, 0.8);
         Text_Centered (Cr, W / 2.0, H / 2.0, "no preview", 12.0);
         return;
      end if;
      R := Gdouble'Min
        (W / (1.5 * Gdouble (P.Cols - 1) + 2.0),
         H / (Sqrt3 * (Gdouble (P.Rows) + 0.5)));
      OX := (W - R * (1.5 * Gdouble (P.Cols - 1) + 2.0)) / 2.0;
      OY := (H - R * Sqrt3 * (Gdouble (P.Rows) + 0.5)) / 2.0;

      declare
         function CX (C : Integer) return Gdouble is
           (OX + R + Gdouble (C) * 1.5 * R);
         function CY (C, Rw : Integer) return Gdouble is
           (OY + R * Sqrt3 / 2.0 + Gdouble (Rw) * R * Sqrt3
            + (if C mod 2 = 1 then R * Sqrt3 / 2.0 else 0.0));

         procedure Small_Hex (X, Y : Gdouble) is
         begin
            for I in 0 .. 5 loop
               declare
                  A : constant Float := Float (I) * Pi / 3.0;
               begin
                  if I = 0 then
                     Move_To (Cr, X + R * Gdouble (EF.Cos (A)),
                              Y + R * Gdouble (EF.Sin (A)));
                  else
                     Line_To (Cr, X + R * Gdouble (EF.Cos (A)),
                              Y + R * Gdouble (EF.Sin (A)));
                  end if;
               end;
            end loop;
            Close_Path (Cr);
         end Small_Hex;
      begin
         for C in 0 .. P.Cols - 1 loop
            for Rw in 0 .. P.Rows - 1 loop
               declare
                  T  : Terrain_Kind;
                  Ok : Boolean;
                  S  : Shade;
               begin
                  From_Char (P.Glyphs (C, Rw), T, Ok);
                  S := (if T = River then (0.40, 0.58, 0.85)
                        elsif T = Road then (0.78, 0.72, 0.55)
                        else Terrain_Color (T));
                  Small_Hex (CX (C), CY (C, Rw));
                  Color (Cr, S.R, S.G, S.B);
                  Fill (Cr);
                  if P.Owner (C, Rw) /= 0 then
                     declare
                        O : constant Shade := Parse
                          (To_String (P.Colors (P.Owner (C, Rw))));
                     begin
                        Small_Hex (CX (C), CY (C, Rw));
                        Color (Cr, O.R, O.G, O.B, 0.55);
                        Fill (Cr);
                     end;
                  end if;
                  if P.Victory (C, Rw) then
                     Small_Hex (CX (C), CY (C, Rw));
                     Color (Cr, 1.0, 0.85, 0.1);
                     Set_Line_Width (Cr, Gdouble'Max (1.5, R * 0.25));
                     Stroke (Cr);
                  end if;
               end;
            end loop;
         end loop;
         for I in 1 .. P.Unit_Count loop
            declare
               U : constant Engine.Loader.Preview_Unit := P.Units (I);
               S : constant Shade :=
                 Parse (To_String (P.Colors (U.Side)));
            begin
               if U.Col in 0 .. P.Cols - 1 and then U.Row in 0 .. P.Rows - 1
               then
                  Rectangle (Cr, CX (U.Col) - R * 0.5,
                             CY (U.Col, U.Row) - R * 0.38, R, R * 0.76);
                  Color (Cr, S.R, S.G, S.B);
                  Fill_Preserve (Cr);
                  Color (Cr, 0.05, 0.05, 0.05);
                  Set_Line_Width (Cr, 0.8);
                  Stroke (Cr);
               end if;
            end;
         end loop;
      end;
   end Draw_Preview;

end Map_Render;
