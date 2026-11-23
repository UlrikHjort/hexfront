-- ***************************************************************************
--                     Hexfront - Oob_Window
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

--  Order of battle: a list of one side's units with their state.
--  Selecting a row picks that unit on the map.
with Gtk.Window;
with Engine;

package Oob_Window is

   type Pick_Callback is access procedure (U : Positive);
   On_Pick : Pick_Callback;

   --  Open (or raise) the window for side S.
   procedure Show (Parent : Gtk.Window.Gtk_Window; S : Engine.Player_Side);

   --  Refill the list if the window is open (call after game changes).
   procedure Update (S : Engine.Side_Id);

   function Is_Open return Boolean;

end Oob_Window;
