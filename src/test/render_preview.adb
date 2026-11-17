--  Renders a scenario chooser preview to PNG (headless check).
with Ada.Command_Line;    use Ada.Command_Line;
with Cairo;               use Cairo;
with Cairo.Image_Surface; use Cairo.Image_Surface;
with Cairo.Png;
with Engine.Loader;
with Map_Render;

procedure Render_Preview is
   P  : Engine.Loader.Preview_Data;
   S  : constant Cairo_Surface := Create (Cairo_Format_ARGB32, 600, 320);
   Cr : constant Cairo_Context := Create (S);
   St : Cairo_Status;
   pragma Unreferenced (St);
begin
   Engine.Loader.Read_Preview (Argument (1), P);
   Map_Render.Draw_Preview (Cr, P, 600.0, 320.0);
   St := Cairo.Png.Write_To_Png (S, Argument (2));
end Render_Preview;
