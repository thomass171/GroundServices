#
#
#

logging.debug("executing mathutil.nas");

var PI = math.pi;
var PI2 = PI * 2;
var PI_2 = PI / 2;
var FLT_EPSILON = 1.19209290E-07;

var Vector3 = {
    
    new: func(x=0,y=0,z=0) {	    
	    var obj = { parents: [Vector3] };
		obj.x = x;
		obj.y = y;
		obj.z = z;
		return obj;
	},
	
	getX: func() {return me.x;},
	getY: func() {return me.y;},
    getZ: func() {return me.z;},
        	
    add: func(v) {
        return Vector3.new(me.x + v.x, me.y + v.y, me.z + v.z);
    },
    
    subtract: func(v) {
        return Vector3.new(me.x - v.x, me.y - v.y, me.z - v.z);
    },
        
    multiply: func(scale) {
        return Vector3.new(me.x * scale, me.y * scale, me.z * scale);
    },
    
    #rotate by degree
    rotate: func(degree) {
        #logging.debug("Vector3:rotate: degree="~degree);
    
        var rad = radianFromDegree(degree);
        var rotXY = rotateXY(me.x,me.y,rad);   
        return Vector3.new(rotXY.x,rotXY.y,0);
    },
            
    length: func () {
        return math.sqrt(me.x * me.x + me.y * me.y + me.z * me.z);
    },
    
    normalize: func () {
        var len = me.length();
        if (math.abs(len) < 0.0000001) {
            return me.clone();
        }
        var no = me.divideScalar(len);
        #logging.debug("normalizing "~me.toString() ~ " to " ~ no.toString());
        return no;
    },
        
    toString: func () {
        return "(" ~ me.x ~ "," ~ me.y ~ "," ~ me.z ~ ")";
    },
    
    divideScalar: func( scalar) {
        var invScalar = 1.0 / scalar;
        return Vector3.new( me.x* invScalar, me.y * invScalar, me.z* invScalar);
    },
		
    clone: func() {
        return Vector3.new( me.x, me.y , me.z);
    },	
    	              	
    negate: func() {
        return Vector3.new( -me.x, -me.y , -me.z);
    },	    	              	
};

var getCrossProduct = func ( a,  b) {
    var x1 =  a.y *  b.z;
    var x2 =  a.z *  b.y;
    var y =  a.z *  b.x -  a.x *  b.z;
    var z =  a.x *  b.y -  a.y *  b.x;
    var output = Vector3.new((x1 - x2),y, z);     
    return output;
};

var getDistanceXYZ = func( p1,  p2) {
    return p1.subtract( p2).length();
};

var getAngleBetween = func( p1,  p2) {
    var dot = getDotProduct(p1.normalize(), p2.normalize());
    if (dot < -1) {
        dot = -1;
    }
    if (dot > 1) {
        dot = 1;
    }
    return math.acos(dot);
};
        
var getDotProduct = func( v1,  v2) {
    var p = v1.x * v2.x + v1.y * v2.y + v1.z * v2.z;
    return p;
};

var rotateXY = func(x,y, radians) {
     #logging.debug("rotateXY: radians="~radians);
     
     var sin = math.sin(radians);
     var cos = math.cos(radians);
     var tx = x;
     var ty = y;
     return {x: (cos * tx) - (sin * ty), y : (sin * tx) + (cos * ty) };
}
         
var degreeFromRadians = func(r) {
    return 180 * r / math.pi;
};

var radianFromDegree = func(angdeg) {
    return angdeg * math.pi / 180;
};

var getHeadingFromDirection = func(vXY) {
    var a = math.atan2(vXY.x, vXY.y);
    if (a < 0) {
        a += math.pi * 2;
    }
    return degreeFromRadians(a);
};

# Result is normalized.
# No deflection(?) compensation!
var getDirectionFromHeading = func(degree) {
    #logging.debug("getDirectionFromHeading: degree="~degree);
    var rad = -radianFromDegree(degree);
    var x = -math.sin(rad);
    var y = math.cos(rad);
    return Vector2.new(x,y);
};

# including deflection(?) compensation
var getTrueHeadingFromDirection = func(coord,vXY) {
    # deflection compensation. TODO optimize calculation
    var direction = geo.Coord.new().set_latlon(coord.lat()+1*vXY.y,coord.lon()+1*vXY.x);    
    var heading = coord.course_to(direction);
    return heading;   
};

var getDegreeFromHeading = func(heading) {
    return (-(90 + heading));
};


# converts angle in degree to heading
var buildRotationZ = func(angdeg) {
    return angdeg;
};

#
# intersection of 2 line in 2D according to Cramer
var getLineIntersection = func( p1,  p2,  p3,  p4) {
    var nenner = (((p4.y - p3.y) * (p2.x - p1.x)) - ((p2.y - p1.y) * (p4.x - p3.x)));
    if (math.abs(nenner) < FLT_EPSILON) {
        return nil;
    }
    var xs = (((p4.x - p3.x) * ((p2.x * p1.y) - (p1.x * p2.y))) - ((p2.x - p1.x) * ((p4.x * p3.y) - (p3.x * p4.y)))) / nenner;
    var ys = (((p1.y - p2.y) * (p4.x * p3.y - p3.x * p4.y)) - ((p3.y - p4.y) * (p2.x * p1.y - p1.x * p2.y))) / nenner;
    return Vector2.new(xs, ys);
};

var isEqual = func (f1,f2,epsilon=FLT_EPSILON) {
    #logging.debug("isequal: " ~ f1 ~ "," ~f2~ ";"~epsilon);
	if (math.abs(f1 - f2) > epsilon) {
	    return 0;
	}	
	return 1;
};

var Vector2 = {
    new: func(x=0,y=0) {	    
	    var obj = { parents: [Vector2] };
		obj.x = x;
		obj.y = y;
		return obj;
	},
	
	getX: func() {return me.x;},
	getY: func() {return me.y;},
	
	add: func(v) {
        return Vector2.new(me.x + v.x, me.y + v.y);
    },
        
    subtract: func(v) {
        return Vector2.new(me.x - v.x, me.y - v.y);
    },
        
    multiply: func(scale) {
        return Vector2.new(me.x * scale, me.y * scale);
    },
    
	#rotate by degree
    rotate: func(degree) {
        #logging.debug("Vector2:rotate: degree="~degree);
    
        var rad = radianFromDegree(degree);
        var rotXY = rotateXY(me.x,me.y,rad);   
        return Vector2.new(rotXY.x,rotXY.y);
    },
  
    negate: func() {
        return Vector2.new( -me.x, -me.y);
    },
    
    length: func () {
        return math.sqrt(me.x * me.x + me.y * me.y);
    },
        
    normalize: func () {
        var len = me.length();
        if (math.abs(len) < 0.0000001) {
            return me.clone();
        }
        var no = me.divideScalar(len);
        return no;
    },
    
    divideScalar: func( scalar) {
        var invScalar = 1.0 / scalar;
        return Vector2.new( me.x* invScalar, me.y * invScalar);
    },
        
    clone: func() {
        return Vector2.new( me.x, me.y);
    },
};
    
var buildFromVector2 = func (vXY) {
    return Vector3.new(vXY.getX(), vXY.getY(), 0);
};

var isPointOnLine = func(startXY, endXY, pXY) {
    if (pXY.getX() < math.min(startXY.getX(), endXY.getX())) {
        return 0;
    }
    if (pXY.getX() > math.max(startXY.getX(), endXY.getX())) {
        return 0;
    }
    if (pXY.getY() < math.min(startXY.getY(), endXY.getY())) {
        return 0;
    }
    if (pXY.getY() > math.max(startXY.getY(), endXY.getY())) {
        return 0;
    }
    return 1;
};

logging.debug("completed mathutil.nas");