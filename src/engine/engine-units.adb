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
