//----------------------------------------------------------------------
// Basket: an open box on a handle, for carrying things.
//
// A basket is concave, and addPolygon takes the convex hull of what it is
// given -- so the hollow cannot be one shape.  It is three boxes on one
// body instead: a floor and two walls.  One body, because the engine has no
// joints; three separate bodies would simply fall apart.
//
// The handle has no shape at all.  It is drawn, and it carries the tie
// point, but nothing collides with it, so a ball can be dropped straight in
// from above.  The picture is drawn in front of everything else on the part
// layer (see Part.drawsInFront), so a ball in the basket is properly inside
// it rather than sitting on top of the weave.
//
// The geometry below is measured off the art, in the part's own frame, with
// the origin at the middle of the picture.  There is no scaling: a basket is
// the size of its sprite.
//----------------------------------------------------------------------

basketImg = file.loadImage("/usr/pics/basket_48x48.png")

// The basket's extent within the 48x48 art: the bowl is 40 wide, and the
// handle takes the height to 44.  Both are centered in the image, so the
// sprite needs no offset from the body.
artWidth = 40
artHeight = 44

// The bowl, in the part's frame: its rim, its underside, and how thick the
// walls and floor are.  The handle arches above the rim up to the tie point.
rimY = 4
baseY = -22
wallThick = 5
floorThick = 6
tieY = 20.5             // the top of the handle strap, where a rope goes

globals.Basket = new Part
Basket.typeName = "basket"
Basket.displayName = "Basket"
// Wicker is light: this density puts the basket at about 24 grams, so one
// balloon (78 g of lift) carries it with a tennis ball aboard and climbs.
// Friction is high and bounce nearly nil, so what lands in it stays in it.
Basket.defaultSpec = Part.defaultSpec + {"density": 0.55,
  "restitution": 0.05, "friction": 0.8,
  "linearDamping": 0.05, "angularDamping": 0.5}

// The footprint includes the handle, which is what the selection ring and
// the grid snap work from, even though nothing collides with it.
Basket.size = function
	return [artWidth, artHeight]
end function

// The one tie point: the top of the handle.  It is a long way above the
// center of mass, which sits down among the floor and walls, so a hanging
// basket rights itself instead of tipping its load out.
Basket.tieLocals = function
	return [[0, tieY]]
end function

Basket.makeBodies = function
	s = self.spec
	b = self.addBody
	half = artWidth / 2
	h = rimY - baseY
	inner = half - wallThick
	// Walls the full depth of the bowl, and a floor let in between them, so
	// that no two shapes overlap and the mass comes out right.
	shapes = [b.addBox(wallThick, h, -half + wallThick / 2, baseY + h / 2, 0, s.density),
	  b.addBox(wallThick, h, half - wallThick / 2, baseY + h / 2, 0, s.density),
	  b.addBox(inner * 2, floorThick, 0, baseY + floorThick / 2, 0, s.density)]
	for sh in shapes
		sh.setRestitution s.restitution
		sh.setFriction s.friction
	end for
end function

//----------------------------------------------------------------------
// Appearance: the art as it comes, one sprite on the one body, drawn over
// the other parts so that a load rides inside the basket.
//----------------------------------------------------------------------

Basket.drawsInFront = true

Basket.imageKey = function
	return "basket"
end function

Basket.makeImage = function
	return basketImg
end function
