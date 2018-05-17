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
    
    #rotate by degree around z axis
    rotateOnZ: func(degree) {
        #logging.debug("Vector3:rotate: degree="~degree);
    
        var rad = radianFromDegree(degree);
        var rotXY = rotateXY(me.x,me.y,rad);   
        return Vector3.new(rotXY.x,rotXY.y,0);
    },
    
    #rotate by quaternion. From https://gamedev.stackexchange.com/questions/28395/rotating-vector3-by-a-quaternion
    #TODO: use rotateOnZ for z0 graphs
    rotate: func(q) {
        #logger.debug("rotate by "~q.toString());
        var u = Vector3.new(q.getX(), q.getY(), q.getZ());
        # Extract the scalar part of the quaternion
        var s = q.getW();
        var result = u.multiply(2.0 * Vector3.getDotProduct(u, me)).add(
            me.multiply(s * s - Vector3.getDotProduct(u, u))).add(
            Vector3.getCrossProduct(u, me).multiply(2.0 * s));
        return result;
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
    
    getCrossProduct: func ( a,  b) {
        var x1 =  a.y *  b.z;
        var x2 =  a.z *  b.y;
        var y =  a.z *  b.x -  a.x *  b.z;
        var z =  a.x *  b.y -  a.y *  b.x;
        var output = Vector3.new((x1 - x2),y, z);     
        return output;
    },
    
    getAngleBetween: func( p1,  p2) {
        var dot = Vector3.getDotProduct(p1.normalize(), p2.normalize());
        if (dot < -1) {
            dot = -1;
        }
        if (dot > 1) {
            dot = 1;
        }
        return math.acos(dot);
    },
    
    getDistanceXYZ: func( p1,  p2) {
        return p1.subtract( p2).length();
    },
            
    getDotProduct: func( v1,  v2) {
        var p = v1.x * v2.x + v1.y * v2.y + v1.z * v2.z;
        return p;
    },
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
#8.5.18 var buildRotationZ = func(angdeg) {
#8.5.18     return angdeg;
#8.5.18 };

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

var isEqualDegree = func( d1, d2 ,epsilon=FLT_EPSILON) {
    d1 = normalizeDegree(d1);
    d2 = normalizeDegree(d2);
    return isEqual(d1,d2,epsilon);
};

var normalizeDegree = func(d) {
    while (d < 0) {
        d += 360;
    }
    while (d > 360){
        d -= 360;
    }
    return d;
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

var buildQuaternionFromAngles = func( xrad,  yrad,  zrad) {
    var sinX = math.sin(xrad * 0.5);
    var cosX = math.cos(xrad * 0.5);
    var sinY = math.sin(yrad * 0.5);
    var cosY = math.cos(yrad * 0.5);
    var sinZ = math.sin(zrad * 0.5);
    var cosZ = math.cos(zrad * 0.5);

    var cosYXcosZ = cosY * cosZ;
    var sinYXsinZ = sinY * sinZ;
    var cosYXsinZ = cosY * sinZ;
    var sinYXcosZ = sinY * cosZ;

    var w = (cosYXcosZ * cosX - sinYXsinZ * sinX);
    var x = (cosYXcosZ * sinX + sinYXsinZ * cosX);
    var y = (sinYXcosZ * cosX + cosYXsinZ * sinX);
    var z = (cosYXsinZ * cosX - sinYXcosZ * sinX);
    
    var quaternion = Quaternion.new(x, y, z, w);
    quaternion = quaternion.normalize();
    return quaternion;
};

var Quaternion = {    
    new: func(x=0,y=0,z=0,w=0) {	    
	    var obj = { parents: [Quaternion] };
#logger.debug("Building quaternion for x"~x);
#logger.debug("Building quaternion for y"~y);
#logger.debug("Building quaternion for z"~z);
#logger.debug("Building quaternion for w"~w);    
		obj.x = x;
		obj.y = y;
		obj.z = z;
		obj.w = w;
		return obj;
	},
	
	getX: func() {return me.x;},
	getY: func() {return me.y;},
    getZ: func() {return me.z;},
    getW: func() {return me.w;},

    normalize: func() {
        var n = math.sqrt(1 / (me.w * me.w + me.x * me.x + me.y * me.y + me.z * me.z));
        return Quaternion.new(me.x * n, me.y * n, me.z * n, me.w * n);
    },
        
    # quaternion for twoe vecvtor rotation
    buildQuaternion: func(fromXYZ, toXYZ) {
        fromXYZ = fromXYZ.normalize();
        toXYZ = toXYZ.normalize();
        var r = 0;
        var v1XYZ = nil;
        var EPS = 0.000001;
    
        r = Vector3.getDotProduct(fromXYZ, toXYZ) + 1;
        if (r < EPS) {
            #opposite
            r = 0;
            if (math.abs(fromXYZ.getX()) > math.abs(fromXYZ.getZ())) {
                v1XYZ = Vector3.new(-fromXYZ.getY(), fromXYZ.getX(), 0);
            } else {
                v1XYZ = Vector3.new(0, -fromXYZ.getZ(), fromXYZ.getY());
            }                
        } else {
            v1XYZ = Vector3.getCrossProduct(fromXYZ, toXYZ);
        }        
        var q = Quaternion.new(v1XYZ.getX(), v1XYZ.getY(), v1XYZ.getZ(), r);
        q = q.normalize();
        return q;        
    },
       
    buildQuaternionFromDegrees: func(xdegree, ydegree, zdegree) {
        return buildQuaternionFromAngles(radianFromDegree(xdegree), radianFromDegree(ydegree), radianFromDegree(zdegree));
    },

    buildQuaternionFromAngleAxis: func(angle, axis) {
        angle = radianFromDegree(angle);
        axis = axis.normalize();
        var halfAngle = 0.5 * angle;
        var sin = math.sin(halfAngle);

        var w = math.cos(halfAngle);
        var x = sin * axis.getX();
        var y = sin * axis.getY();
        var z = sin * axis.getZ();
        return Quaternion.new(x, y, z, w).normalize();
    },
    
    buildRotationZ: func(degree) {
        return buildQuaternionFromAngles(0,0, degree);
    },
    
    multiply: func(q) {
        var qw = q.getW();
        var qx = q.getX();
        var qy = q.getY();
        var qz = q.getZ();
        var res = Quaternion.new(
            me.getX() * qw + me.getY() * qz - me.getZ() * qy + me.getW() * qx,
            -me.getX() * qz + me.getY() * qw + me.getZ() * qx + me.getW() * qy,
            me.getX() * qy - me.getY() * qx + me.getZ() * qw + me.getW() * qz,
            -me.getX() * qx - me.getY() * qy - me.getZ() * qz + me.getW() * qw);
        return res;
    },
    
    buildLookRotation: func(forward, up) {
        forward = forward.normalize();
        up = up.normalize();
        var right = Vector3.getCrossProduct(up, forward).normalize();
        up = Vector3.getCrossProduct(forward, right).normalize();

        return me.extractQuaternion(
            right.getX(), up.getX(), forward.getX(),
            right.getY(), up.getY(), forward.getY(),
            right.getZ(), up.getZ(), forward.getZ());    
    },
    
    extractQuaternion: func(m00, m01, m02,
        m10, m11, m12,
        m20, m21, m22) {
       
        var trace = m00 + m11 + m22;
        var x=0;
        var y=0;
        var z=0;
        var w=0;
    
        if (trace >= 0) {
            var s = math.sqrt(trace + 1);
            w = 0.5 * s;
            s = 0.5 / s;
            x = (m21 - m12) * s;
            y = (m02 - m20) * s;
            z = (m10 - m01) * s;
        } else if ((m00 > m11) and (m00 > m22)) {
            var s = math.sqrt(1.0 + m00 - m11 - m22);
            x = s * 0.5;
            s = 0.5 / s;
            y = (m10 + m01) * s;
            z = (m02 + m20) * s;
            w = (m21 - m12) * s;
        } else if (m11 > m22) {
            var s = math.sqrt(1.0 + m11 - m00 - m22);
            y = s * 0.5;
            s = 0.5 / s;
            x = (m10 + m01) * s;
            z = (m21 + m12) * s;
            w = (m02 - m20) * s;
        } else {
            var s = math.sqrt(1.0 + m22 - m00 - m11);
            z = s * 0.5;
            s = 0.5 / s;
            x = (m02 + m20) * s;
            y = (m21 + m12) * s;
            w = (m10 - m01) * s;
        }
        var q = Quaternion.new(x, y, z, w);
        q = q.normalize();
        return q;
    },
    
    toString: func () {
        return "(" ~ me.x ~ "," ~ me.y ~ "," ~ me.z ~ "," ~ me.w ~ ")";
    },
};

logging.debug("completed mathutil.nas");