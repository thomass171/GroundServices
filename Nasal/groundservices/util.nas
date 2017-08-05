#
#
#

logging.debug("executing util.nas");

var FloatMAX_VALUE = 3.4028234664e+38;

var getXmlAttrStringValue = func(xmlnode,attrname) {
    var attrchild = xmlnode.getChild("___"~attrname);
    #logging.debug(attrname~":"~dumpObject(xmlnode)~dumpObject(attrchild));
    if (attrchild == nil) {
        return nil;
    }
    return attrchild.getValue();
};

var getXmlFloatAttribute = func(node, attrname, defaultvalue) {
    var s = getXmlAttrStringValue(node, attrname);
    if (s==nil or s==""){
        return defaultvalue;
    }
    return num(s);
};
    
var parseDegree = func(s) {
    #logging.debug("parse "~s);
    var f = s[0];
    if (string.isdigit(f))
        return num(s);
        
    var parts = split(" ",s);
    var minuten = num(parts[1]);
    var degree = num(substr(parts[0],1));
    var d = degree+minuten/60;
    if (f=="W" or f=="S"){
        d = -d;
    }
    return d;
};

# from debug.nas
var dumpObject = func(o) {
    var t = typeof(o);
    if (t == "nil") {
        return "nil";#_nil("nil", color);

    } elsif (t == "scalar") {
        return o;#num(o) == nil ? _dump_string(o, color) : _num(o~"", color);

    } elsif (t == "vector") {
        return("vector.size:"~size(o)); 
        #var s = "";
        #forindex (var i; o)
        #    s ~= (i == 0 ? "" : ", ") ~ debug.string(o[i], color);
        #return _bracket("[", color) ~ s ~ _bracket("]", color);

    } elsif (t == "hash") {
        #if (contains(o, "parents") and typeof(o.parents) == "vector"
        #        and size(o.parents) == 1 and o.parents[0] == props.Node)
        #    return _angle("<", color) ~ _dump_prop(o, color) ~ _angle(">", color);

        var k = keys(o);
        var s = "";
        forindex (var i; k)
            s ~= (i == 0 ? "" : ", ") ~ k[i];#_dump_key(k[i], color) ~ ": ";# ~ debug.string(o[k[i]], color);
        return ("hash.keys:"~s);#_brace("{", color) ~ " " ~ s ~ " " ~ _brace("}", color);

    } elsif (t == "ghost") {
        return "ghost";#_angle("<", color) ~ _nil(ghosttype(o), color) ~ _angle(">", color);

    } else {
        #return _angle("<", color) ~ _vartype(t, color) ~ _angle(">", color);
    }
    return "unknown type";
};

var insertIntoList = func(list, index, element) {
    append(list,nil);
    for (var i=size(list)-1;i > index;i-=1){
        list[i] = list[i-1];
    }
    list[index] = element;
};

var buildTearDropTurn = func(e1, e2, turnloop) {
    return { edge: e1, branch : e2, arc : turnloop};                
};

var getCurrentAltitude = func() {
    var pos = geo.aircraft_position();    
    var alt = airportelevation; #default 
    var info = geodinfo(pos.lat(), pos.lon());
    if (info != nil) {
        alt = num(info[0]);
        logging.debug("altitude="~alt~" "~info[0]);
    } else {
        logging.warn("no current altitide. using airportelevation "~alt);
    }
    #TODO +5?
    return alt;
};

#Return random int from 0 to 32767
var randnextInt = func() {
    var r = math.round(rand()*32767);
    logging.debug("random int="~r);
    return r;
};
	
var buildXY = func(x,y) {
	return { x :x,y:y};
};

var Projection = {
    METERPERDEGREE : 1850 * 60,
    
	new: func(origin) {	    
	    var obj = { parents: [Projection] };
		obj.origin = origin;		
		return obj;
	},
	
	project: func (coorCoord) {
	    var x = (coorCoord.lon() - me.origin.lon()) * Projection.METERPERDEGREE;
	    var y = (coorCoord.lat() - me.origin.lat()) * Projection.METERPERDEGREE;
	    #logging.debug("project: lat=" ~ coorCoord.lat() ~ ",lon=" ~ coorCoord.lon() ~ ",origin.lat=" ~ me.origin.lat() ~ ",origin.lon=" ~ me.origin.lon() ~ " to "~x~","~y);     	   
	    return buildXY(x,y);
    },
        
    unproject: func (locXY) {
        #logging.debug("unproject: x=" ~ locXY.x ~ ",y=" ~ locXY.y ~ ",origin.lat=" ~ me.origin.lat() ~ ",origin.lon=" ~ me.origin.lon());
    	    
        return geo.Coord.new().set_latlon(me.origin.lat() + (locXY.y / Projection.METERPERDEGREE),me.origin.lon() + (locXY.x / Projection.METERPERDEGREE),400);               
    }        	
};

var validateObject = func(obj,objname,expectedclassname) {
    if (obj == nil) {
        # also error
        logging.error("object is nil");
        return 1;
    }
    var t = typeof(obj);
    if (t == "nil") {
        logging.error("no type");
        return 1;        
    } elsif (t == "scalar") {
        logging.error("no class");
        return 1;   
    } elsif (t == "vector") {
        logging.error("no class");
        return 1;   
    } elsif (t == "hash") {
        #if (contains(o, "parents") and typeof(o.parents) == "vector"
        #        and size(o.parents) == 1 and o.parents[0] == props.Node)
        #    return _angle("<", color) ~ _dump_prop(o, color) ~ _angle(">", color);
        if (!contains(obj, "parents")) {
            logging.error("no class (no parents)");
            return 1; 
        }
        # only exit for valid
        return 0;
    }
    logging.error("no class (no type hash)");
    return 1; 
};


logging.debug("completed util.nas");