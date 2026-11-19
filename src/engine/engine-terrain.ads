package Engine.Terrain is
   pragma Pure;

   type Terrain_Kind is
     (Clear, Road, Forest, Hills, Mountain, River, Swamp,
      Town, City, Fortress, Water, Trench, Airfield);

   type Move_Class is (Foot, Horse, Wheeled, Tracked, Static, Air, Naval);

   Impassable : constant := 99;

   function Move_Cost (T : Terrain_Kind; M : Move_Class) return Natural;

   --  Added to the defence value of a unit standing in this terrain.
   function Defense_Bonus (T : Terrain_Kind) return Integer;

   --  Close terrain hampers vehicles and charging cavalry.
   function Is_Close (T : Terrain_Kind) return Boolean is
     (T in Forest | Mountain | Town | City | Fortress | Swamp);

   --  Terrain that can be owned and captured.
   function Is_Capturable (T : Terrain_Kind) return Boolean is
     (T in Town | City | Fortress | Airfield);

   procedure From_Char
     (C : Character; T : out Terrain_Kind; Ok : out Boolean);

   function Name (T : Terrain_Kind) return String;
end Engine.Terrain;
