with Ada.Calendar;            use Ada.Calendar;
with Ada.Numerics;            use Ada.Numerics;
with Ada.Strings.Unbounded;   use Ada.Strings.Unbounded;
with Glib.Main;
with Engine;                  use type Engine.Side_Id;
with Engine.Hexes;            use Engine.Hexes;
with Engine.Terrain;          use Engine.Terrain;
with Engine.Units;            use Engine.Units;
with Engine.Game;             use Engine.Game;
with Map_Render;
with Sound;

package body Anim is

   use Cairo;

   Queue   : Fx_Vectors.Vector;
   Current : Fx_Event;
   Active  : Boolean := False;
   Started : Time;
   Length  : Duration := 0.0;
   Ticking : Boolean := False;

   function Busy return Boolean is (Active or else not Queue.Is_Empty);

   procedure Clear is
   begin
      Queue.Clear;
      Active := False;
   end Clear;

   ------------
   -- Sounds --
   ------------

   function Era_Is (Id : String) return Boolean is
     (To_String (G.Era.Id) = Id);

   procedure Sound_For (E : Fx_Event) is
   begin
      case E.Kind is
         when Fx_Move =>
            if E.Unit /= 0 then
               Sound.Play
                 (case Type_Of (E.Unit).Mover is
                     when Foot | Static => "move_foot",
                     when Horse   => "move_horse",
                     when Wheeled => "move_wheels",
                     when Tracked => "move_tracks",
                     when Air     => "move_air");
            end if;
         when Fx_Combat =>
            if E.Air_Attack then
               Sound.Play (if E.Kind_Of_Fire = Bomber then "fire_bomb"
                           else "fire_air");
            else
               case E.Kind_Of_Fire is
                  when Artillery =>
                     Sound.Play (if Era_Is ("napoleonic") then "fire_cannon"
                                 else "fire_artillery");
                  when Armor | Anti_Tank | Anti_Air | Fortification =>
                     Sound.Play ("fire_gun");
                  when others =>
                     Sound.Play (if Era_Is ("napoleonic") then "fire_musket"
                                 elsif Era_Is ("ww1") then "fire_mg"
                                 else "fire_rifle");
               end case;
            end if;
         when Fx_Destroyed => Sound.Play ("explosion");
         when Fx_Capture   => Sound.Play ("capture");
         when Fx_Deploy    => Sound.Play ("deploy");
         when Fx_Victory =>
            declare
               S : constant Engine.Side_Id := Engine.Side_Id (E.Unit);
               Human_Won : constant Boolean :=
                 S in Engine.Player_Side
                 and then (G.Sides (S).Control = Human
                           or else (G.Sides (1).Control = Computer
                                    and then G.Sides (2).Control = Computer));
            begin
               Sound.Play (if Human_Won then "victory" else "defeat");
            end;
      end case;
   end Sound_For;

   function Duration_Of (E : Fx_Event) return Duration is
   begin
      case E.Kind is
         when Fx_Move      =>
            return Duration'Max (0.15, 0.11 * Duration (E.Len - 1));
         when Fx_Combat    => return 0.7;
         when Fx_Destroyed => return 0.8;
         when Fx_Capture | Fx_Deploy => return 0.45;
         when Fx_Victory   => return 0.0;
      end case;
   end Duration_Of;

   ------------
   -- Driver --
   ------------

   function Tick return Boolean;

   procedure Start_Next is
   begin
      while not Queue.Is_Empty loop
         Current := Queue.First_Element;
         Queue.Delete_First;
         Sound_For (Current);
         Length := (if Enabled then Duration_Of (Current) else 0.0);
         if Length > 0.0 then
            Active  := True;
            Started := Clock;
            return;
         end if;
      end loop;
      Active := False;
   end Start_Next;

   function Tick return Boolean is
   begin
      if Active and then Clock - Started >= Length then
         Start_Next;
      end if;
      if On_Redraw /= null then
         On_Redraw.all;
      end if;
      if not Active then
         Ticking := False;
         if On_Done /= null then
            On_Done.all;
         end if;
         return False;
      end if;
      return True;
   end Tick;

   procedure Enqueue (Viewer : Engine.Side_Id) is
      function Seen (H : Hex) return Boolean is
        (Viewer = 0 or else not G.Fog
         or else (In_Map (H) and then G.Seen (Viewer) (H.Col, H.Row)));
   begin
      for E of Effects loop
         declare
            Show : Boolean;
         begin
            case E.Kind is
               when Fx_Move =>
                  Show := Viewer = 0
                    or else Get (E.Unit).Side = Viewer
                    or else (Get (E.Unit).Alive
                             and then Visible (E.Unit, Viewer));
               when Fx_Combat =>
                  Show := Seen (E.From) or else Seen (E.To);
               when Fx_Destroyed | Fx_Capture | Fx_Deploy =>
                  Show := Seen (E.To);
               when Fx_Victory =>
                  Show := True;
            end case;
            if Show then
               Queue.Append (E);
            end if;
         end;
      end loop;
      Effects.Clear;
      if not Active then
         Start_Next;
      end if;
      if Active and then not Ticking then
         Ticking := True;
         declare
            Id : constant Glib.Main.G_Source_Id :=
              Glib.Main.Timeout_Add (30, Tick'Access);
            pragma Unreferenced (Id);
         begin
            null;
         end;
      end if;
   end Enqueue;

   function Progress return Gdouble is
     (if Length <= 0.0 then 1.0
      else Gdouble'Min (1.0, Gdouble ((Clock - Started) / Length)));

   --------------
   -- Override --
   --------------

   function Override (U : Engine.Units.Unit_Index;
                      X, Y : out Gdouble) return Boolean is
   begin
      X := 0.0;
      Y := 0.0;
      if not Active or else Current.Kind /= Fx_Move or else Current.Unit /= U
        or else Current.Len < 2
      then
         return False;
      end if;
      declare
         Steps : constant Gdouble := Gdouble (Current.Len - 1);
         P     : constant Gdouble := Progress * Steps;
         I     : constant Natural :=
           Natural'Min (Current.Len - 1, Natural (Gdouble'Floor (P)) + 1);
         F     : constant Gdouble := P - Gdouble (I - 1);
         A     : constant Hex := Current.Path (I);
         B     : constant Hex := Current.Path (Natural'Min (I + 1,
                                                            Current.Len));
      begin
         X := Map_Render.Center_X (A)
           + (Map_Render.Center_X (B) - Map_Render.Center_X (A)) * F;
         Y := Map_Render.Center_Y (A)
           + (Map_Render.Center_Y (B) - Map_Render.Center_Y (A)) * F;
      end;
      return True;
   end Override;

   ------------------
   -- Draw_Overlay --
   ------------------

   procedure Burst (Cr : Cairo_Context; H : Hex; T : Gdouble;
                    Size : Gdouble) is
      CX : constant Gdouble := Map_Render.Center_X (H);
      CY : constant Gdouble := Map_Render.Center_Y (H);
      R  : constant Gdouble := Size * (0.3 + 0.7 * T);
   begin
      Set_Source_Rgba (Cr, 1.0, 0.85, 0.2, 0.9 * (1.0 - T));
      Arc (Cr, CX, CY, R * 0.6, 0.0, 2.0 * Pi);
      Fill (Cr);
      Set_Source_Rgba (Cr, 1.0, 0.4, 0.05, 0.8 * (1.0 - T));
      Set_Line_Width (Cr, 4.0);
      Arc (Cr, CX, CY, R, 0.0, 2.0 * Pi);
      Stroke (Cr);
   end Burst;

   procedure Float_Text (Cr : Cairo_Context; H : Hex; T : Gdouble;
                         Text : String) is
      CX : constant Gdouble := Map_Render.Center_X (H);
      CY : constant Gdouble := Map_Render.Center_Y (H) - 10.0 - 25.0 * T;
   begin
      Select_Font_Face (Cr, "Sans", Cairo_Font_Slant_Normal,
                        Cairo_Font_Weight_Bold);
      Set_Font_Size (Cr, 16.0);
      Set_Source_Rgba (Cr, 0.0, 0.0, 0.0, 1.0 - T);
      Move_To (Cr, CX - 9.0, CY + 1.0);
      Show_Text (Cr, Text);
      Set_Source_Rgba (Cr, 1.0, 0.15, 0.1, 1.0 - T);
      Move_To (Cr, CX - 10.0, CY);
      Show_Text (Cr, Text);
   end Float_Text;

   function Img (N : Natural) return String is
      S : constant String := Natural'Image (N);
   begin
      return S (S'First + 1 .. S'Last);
   end Img;

   procedure Draw_Overlay (Cr : Cairo_Context) is
      T : constant Gdouble := Progress;
   begin
      if not Active then
         return;
      end if;
      case Current.Kind is
         when Fx_Combat =>
            --  Muzzle flash, tracer line, impact burst, loss numbers.
            if T < 0.35 then
               Set_Source_Rgba (Cr, 1.0, 0.9, 0.4, 0.9);
               Set_Line_Width (Cr, 2.0);
               Move_To (Cr, Map_Render.Center_X (Current.From),
                        Map_Render.Center_Y (Current.From));
               Line_To (Cr, Map_Render.Center_X (Current.To),
                        Map_Render.Center_Y (Current.To));
               Stroke (Cr);
               Burst (Cr, Current.From, T * 2.0, 14.0);
            end if;
            if T > 0.15 then
               Burst (Cr, Current.To, (T - 0.15) / 0.85, 26.0);
            end if;
            if Current.D_Loss > 0 then
               Float_Text (Cr, Current.To, T, "-" & Img (Current.D_Loss));
            end if;
            if Current.A_Loss > 0 then
               Float_Text (Cr, Current.From, T, "-" & Img (Current.A_Loss));
            end if;
         when Fx_Destroyed =>
            Burst (Cr, Current.To, T, 40.0);
            Set_Source_Rgba (Cr, 0.25, 0.25, 0.25, 0.6 * (1.0 - T));
            Arc (Cr, Map_Render.Center_X (Current.To),
                 Map_Render.Center_Y (Current.To) - 20.0 * T,
                 12.0 + 14.0 * T, 0.0, 2.0 * Pi);
            Fill (Cr);
         when Fx_Capture | Fx_Deploy =>
            Set_Source_Rgba (Cr, 1.0, 1.0, 0.6, 0.9 * (1.0 - T));
            Set_Line_Width (Cr, 5.0);
            Arc (Cr, Map_Render.Center_X (Current.To),
                 Map_Render.Center_Y (Current.To),
                 10.0 + 25.0 * T, 0.0, 2.0 * Pi);
            Stroke (Cr);
         when Fx_Move | Fx_Victory =>
            null;
      end case;
   end Draw_Overlay;

end Anim;
