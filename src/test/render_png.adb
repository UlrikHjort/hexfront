--  Renders a scenario map to a PNG (for checking graphics headless).
--
--  render_png scenario.scn out.png [options]
--  options (comma separated): sil      unit silhouettes
--                             supply   supply overlay for the side to move
--                             turns=N  let the computer play N turns first
--                             rain|snow|fog|overcast  force the weather
--                             mini     also write out.png.mini.png
with Ada.Command_Line;    use Ada.Command_Line;
with Ada.Strings.Fixed;   use Ada.Strings.Fixed;
with Cairo;               use Cairo;
with Cairo.Image_Surface; use Cairo.Image_Surface;
with Cairo.Png;
with Glib;                use Glib;
with Engine;              use type Engine.Side_Id;
with Engine.Game;         use Engine.Game;
with Engine.Loader;
with Engine.AI;
with Map_Render;          use Map_Render;

procedure Render_Png is
   W, H : Gint;
   S    : Cairo_Surface;
   Cr   : Cairo_Context;
   V    : View_State;
   St   : Cairo_Status;
   pragma Unreferenced (St);
   Opt  : constant String := (if Argument_Count >= 3 then Argument (3)
                              else "");

   function Has (K : String) return Boolean is (Index (Opt, K) > 0);

   function Turns return Natural is
      P : constant Natural := Index (Opt, "turns=");
      E : Natural;
   begin
      if P = 0 then
         return 0;
      end if;
      E := P + 6;
      while E <= Opt'Last and then Opt (E) in '0' .. '9' loop
         E := E + 1;
      end loop;
      return Natural'Value (Opt (P + 6 .. E - 1));
   end Turns;
begin
   Record_Effects := False;
   Engine.Loader.Load_Scenario (Argument (1));
   G.Sides (1).Control := Computer;
   G.Sides (2).Control := Computer;
   for T in 1 .. 2 * Turns loop
      exit when G.Winner /= 0;
      Engine.AI.Begin_Turn;
      while Engine.AI.Step loop
         null;
      end loop;
      End_Turn;
   end loop;
   if Has ("rain") then
      G.Weather := Rain;
   elsif Has ("snow") then
      G.Weather := Snow;
   elsif Has ("fog") then
      G.Weather := Mist;
   elsif Has ("overcast") then
      G.Weather := Overcast;
   end if;
   Silhouettes := Has ("sil");
   V.Show_Supply := Has ("supply");
   V.Viewer := 0;
   Map_Size (W, H);
   S  := Create (Cairo_Format_ARGB32, W, H);
   Cr := Create (S);
   for I in G.Units.First_Index .. G.Units.Last_Index loop
      if G.Units (I).Alive and then G.Units (I).Side = G.Current then
         V.Selected := I;
         Compute_Reach (I, V.Reach);
         V.Show_Reach := True;
         exit;
      end if;
   end loop;
   Draw (Cr, V);
   St := Cairo.Png.Write_To_Png (S, Argument (2));
   Destroy (Cr);
   Surface_Destroy (S);
   if Has ("mini") then
      S  := Create (Cairo_Format_ARGB32, 320, 130);
      Cr := Create (S);
      Draw_Minimap (Cr, 320.0, 130.0, 0, 100.0, 50.0, 500.0, 300.0);
      St := Cairo.Png.Write_To_Png (S, Argument (2) & ".mini.png");
      Destroy (Cr);
      Surface_Destroy (S);
   end if;
end Render_Png;
