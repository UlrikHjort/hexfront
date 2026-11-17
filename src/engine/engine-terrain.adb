package body Engine.Terrain is

   I : constant := Impassable;

   type Cost_Row is array (Move_Class) of Natural;
   type Cost_Table is array (Terrain_Kind) of Cost_Row;

   --                       Foot Horse Wheel Track Static Air
   Costs : constant Cost_Table :=
     (Clear    => (1, 1, 2, 1, I, 1),
      Road     => (1, 1, 1, 1, I, 1),
      Forest   => (2, 2, 4, 3, I, 1),
      Hills    => (2, 2, 3, 2, I, 1),
      Mountain => (3, 4, I, I, I, 1),
      River    => (3, 3, I, 4, I, 1),
      Swamp    => (3, 3, I, 4, I, 1),
      Town     => (1, 1, 1, 1, I, 1),
      City     => (1, 1, 1, 1, I, 1),
      Fortress => (1, 1, 1, 1, I, 1),
      Water    => (I, I, I, I, I, 1),
      Trench   => (2, 3, 3, 2, I, 1),
      Airfield => (1, 1, 1, 1, I, 1));

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
