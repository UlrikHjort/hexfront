-- ***************************************************************************
--                   Hexfront - Render_Preview
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
