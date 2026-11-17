--  Renders a scenario map to a PNG (for checking graphics headless).
with Ada.Command_Line;    use Ada.Command_Line;
with Cairo;               use Cairo;
with Cairo.Image_Surface; use Cairo.Image_Surface;
with Cairo.Png;
with Glib;                use Glib;
with Engine.Game;         use Engine.Game;
with Engine.Loader;
with Map_Render;          use Map_Render;

procedure Render_Png is
   W, H : Gint;
   S    : Cairo_Surface;
   Cr   : Cairo_Context;
   V    : View_State;
   St   : Cairo_Status;
   pragma Unreferenced (St);
begin
   Engine.Loader.Load_Scenario (Argument (1));
   Map_Size (W, H);
   S  := Create (Cairo_Format_ARGB32, W, H);
   Cr := Create (S);
   V.Selected := 1;
   Compute_Reach (1, V.Reach);
   V.Show_Reach := True;
   V.Viewer := 0;
   Draw (Cr, V);
   St := Cairo.Png.Write_To_Png (S, Argument (2));
   Destroy (Cr);
   Surface_Destroy (S);
end Render_Png;
