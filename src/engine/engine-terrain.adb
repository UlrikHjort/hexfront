-- ***************************************************************************
--                   Hexfront - Engine.Terrain
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

package body Engine.Terrain is

   I : constant := Impassable;

   type Cost_Row is array (Move_Class) of Natural;
   type Cost_Table is array (Terrain_Kind) of Cost_Row;

   --                       Foot Horse Wheel Track Static Air Naval
   Costs : constant Cost_Table :=
     (Clear    => (1, 1, 2, 1, I, 1, I),
      Road     => (1, 1, 1, 1, I, 1, I),
      Forest   => (2, 2, 4, 3, I, 1, I),
      Hills    => (2, 2, 3, 2, I, 1, I),
      Mountain => (3, 4, I, I, I, 1, I),
      River    => (3, 3, I, 4, I, 1, I),
      Swamp    => (3, 3, I, 4, I, 1, I),
      Town     => (1, 1, 1, 1, I, 1, I),
      City     => (1, 1, 1, 1, I, 1, I),
      Fortress => (1, 1, 1, 1, I, 1, I),
      Water    => (I, I, I, I, I, 1, 1),
      Trench   => (2, 3, 3, 2, I, 1, I),
      Airfield => (1, 1, 1, 1, I, 1, I));

   function Move_Cost (T : Terrain_Kind; M : Move_Class) return Natural is
     (Costs (T) (M));

   function Defense_Bonus (T : Terrain_Kind) return Integer is
   begin
      case T is
         when Clear | Road   => return 0;
         when Forest | Hills => return 2;
         when Mountain       => return 4;
         when River | Swamp  => return -1;
         when Town           => return 2;
         when City           => return 3;
         when Fortress       => return 5;
         when Trench         => return 2;
         when Water | Airfield => return 0;
      end case;
   end Defense_Bonus;

   procedure From_Char
     (C : Character; T : out Terrain_Kind; Ok : out Boolean) is
   begin
      Ok := True;
      case C is
         when '.' => T := Clear;
         when '=' => T := Road;
         when 'f' => T := Forest;
         when 'h' => T := Hills;
         when 'M' => T := Mountain;
         when '~' => T := River;
         when 's' => T := Swamp;
         when 't' => T := Town;
         when 'C' => T := City;
         when 'F' => T := Fortress;
         when 'w' => T := Water;
         when '#' => T := Trench;
         when 'A' => T := Airfield;
         when others =>
            T := Clear;
            Ok := False;
      end case;
   end From_Char;

   function Name (T : Terrain_Kind) return String is
   begin
      case T is
         when Clear    => return "Clear";
         when Road     => return "Road";
         when Forest   => return "Forest";
         when Hills    => return "Hills";
         when Mountain => return "Mountains";
         when River    => return "River";
         when Swamp    => return "Swamp";
         when Town     => return "Town";
         when City     => return "City";
         when Fortress => return "Fortress";
         when Water    => return "Water";
         when Trench   => return "Trenches";
         when Airfield => return "Airfield";
      end case;
   end Name;

end Engine.Terrain;
