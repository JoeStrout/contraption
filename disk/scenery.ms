// scenery.ms
// What every level has and nobody placed: the floor, and the walls either
// side.  Its own module so that the game and the headless simulator
// (tools/sim) put exactly the same world around a puzzle.

import "importUtil"
ensureImport ["config", "physics", "part"]

// The floor is scenery: it collides, but it is not a part you can pick up.
// It gets no sprite, because the background art already draws it.
globals.Floor = new Part
Floor.typeName = "floor"
Floor.displayName = "Floor"
Floor.bodyType = physics.STATIC
Floor.fixed = true
Floor.defaultSpec = Part.defaultSpec + {"width": config.fieldWidth,
  "height": config.floorHeight}
Floor.size = function
	return [self.spec.width, self.spec.height]
end function
Floor.makeBodies = function
	b = self.addBody
	sh = b.addBox(self.spec.width, self.spec.height)
	sh.setFriction 0.7
	sh.setRestitution 0.2
end function
Floor.makeSprites = function
end function

// Walls, so that parts cannot be shoved out of the world during play.  Tall
// and thin, just outside the playfield.
globals.Wall = new Floor
Wall.typeName = "wall"
Wall.defaultSpec = Part.defaultSpec + {"width": 20,
  "height": config.fieldHeight * 3}

addTo = function(world)
	world.addPart Floor.make({"x": config.fieldWidth / 2,
	  "y": config.floorHeight / 2})
	world.addPart Wall.make({"x": -10, "y": config.fieldHeight})
	world.addPart Wall.make({"x": config.fieldWidth + 10, "y": config.fieldHeight})
end function
