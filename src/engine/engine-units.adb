-- ***************************************************************************
--                    Hexfront - Engine.Units
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

package body Engine.Units is
   function Class_Name (C : Unit_Class) return String is
   begin
      case C is
         when Infantry      => return "Infantry";
         when Cavalry       => return "Cavalry";
         when Armor         => return "Armour";
         when Recon         => return "Recon";
         when Artillery     => return "Artillery";
         when Anti_Tank     => return "Anti-tank";
         when Anti_Air      => return "Anti-aircraft";
         when Fighter       => return "Fighter";
         when Bomber        => return "Bomber";
         when Engineer      => return "Engineers";
         when Fortification => return "Fortification";
         when Warship       => return "Warship";
      end case;
   end Class_Name;
end Engine.Units;
