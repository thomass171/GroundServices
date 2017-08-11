#
#
#

logging.debug("executing Groundnet.nas");

var SMOOTHINGRADIUS = 10;
var MINIMUMPATHSEGMENTLEN = 2 * SMOOTHINGRADIUS;
var layerid = 0;

var Groundnet = {
    
    new: func(projection, groundnetNode, homename) {	    
	    var obj = { parents: [Groundnet] };
		obj.groundnetgraph = Graph.new();
		#string->node
		obj.parkposname2node = {};
		obj.home = nil;
		#logging.debug("groundnetNode "~groundnetNode.getName());
		
        var nodelist = groundnetNode.getChild("TaxiNodes",0).getChildren("node");
        for (i = 0; i < size(nodelist); i=i+1) {
            var node = nodelist[i];
            #logging.debug("node "~i~node.getName());
            var n = obj.addNode(obj.groundnetgraph, projection, node);
            
        }
        nodelist = groundnetNode.getChild("parkingList",0).getChildren("Parking");
        for (i = 0; i < size(nodelist); i=i+1) {
            var node = nodelist[i];
            #logging.debug("node "~i~node.getName());
            var n = obj.addNode(obj.groundnetgraph, projection, node);
            var parkingname = getXmlAttrStringValue(node, "name");
            #n.customdata = { type:"P", name: parkingname, node : n};
            n.customdata = Parking.new(n, parkingname, getXmlFloatAttribute(node, "heading", 0), getXmlFloatAttribute(node, "pushBackRoute", -1), getXmlFloatAttribute(node, "radius", 0));
            if (homename != nil and homename == parkingname){
                obj.home = n.customdata;                
            }
        }
        nodelist = groundnetNode.getChild("TaxiWaySegments",0).getChildren("arc");
        for (i = 0; i < size(nodelist); i=i+1) {
            var node = nodelist[i];
            var begin =  getXmlAttrStringValue(node, "begin");
            var end =  getXmlAttrStringValue(node, "end");
            var name = getXmlAttrStringValue(node, "name");
            var bn = obj.groundnetgraph.findNodeByName(begin);
            var en = obj.groundnetgraph.findNodeByName(end);
            if (bn == nil) {
                logger.warn("begin node not found: " ~ begin);
            } else {
                if (en == nil) {
                    logger.warn("end node not found: " ~ end);
                } else {
                    var c = obj.groundnetgraph.findConnection(bn, en);
                    if (c == nil) {
                        var longname = "" ~ begin ~ "->" ~ end ~ "(" ~ name ~ ")";
                        var shortname = "" ~ begin ~ "-" ~ end;
                        c = obj.groundnetgraph.connectNodes(bn, en, shortname);
                        #TODO c.customdata = TaxiwaySegment.new(c, name, XmlHelper.getBooleanAttribute(node, "isPushBackRoute", false));
                    }
                }
            }
        }
        var someparkingposwithoneedge = nil;
        if (obj.home == nil) {
            for (var i = 0; i < obj.groundnetgraph.getNodeCount(); i+=1) {
                var n = obj.groundnetgraph.getNode(i);
                if (obj.isParking(n)) {
                    if (n.getEdgeCount() == 1) {
                        someparkingposwithoneedge = n.customdata;
                    }                
                    if (n.customdata.getApproach() != nil) {
                        obj.home = n.customdata;
                        break;
                    }
                }
            }
        }
        if (obj.home == nil) {
            #No possible home position found. Inconsistent groundnet? Simply pick one of the parking positions with exactly one edge as home
            logging.warn("no parking position suitable as home found. Using any one");
            if (someparkingposwithoneedge != nil) {
                obj.home = someparkingposwithoneedge;
            }
        }
        
        logging.info("groundnet home is " ~ ((obj.home == nil)?" unset":obj.home.name));
        
		return obj;
	},
	
    addNode: func(groundnetgraph, projection, node) {
	    var name = getXmlAttrStringValue(node,"index");
        var latDeg = parseDegree(getXmlAttrStringValue(node,"lat"));
        var lonDeg = parseDegree(getXmlAttrStringValue(node,"lon"));
        #logging.debug("index="~name~latDeg);
        var coord = geo.Coord.new().set_latlon(latDeg,lonDeg);
        var xy = projection.project(coord);
        var altinfo = getElevationForLocation(coord);
        var alt = altinfo.alt;        
        # Elevation will be stored in z-Coordinate            
        var node = groundnetgraph.addNode(name, Vector3.new(xy.x,xy.y,alt));
        node.coord = geo.Coord.new().set_latlon(latDeg,lonDeg);
        return node;
	},
		        	
    # get park pos by logical groundnet name. Returns Parking customdata
    getParkPos: func(name) {
        var n = me.parkposname2node[name];
        if (n != nil) {
            return n.customdata;
        }
        for (i = 0; i < me.groundnetgraph.getNodeCount(); i=i+1) {
            n = me.groundnetgraph.getNode(i);
            if (me.isParking(n)) {
                if (n.customdata.name == name) {
                    me.parkposname2node[name]= n;
                    return n.customdata;
                }
            }
        }
        #not found
        return nil;
    },

    isParking: func(n){    
        var customdata = n['customdata'];
        if (customdata == nil){
            return 0;
        }
        if (customdata.type == nil){
            return 0;
        }
        if (customdata.type == "P"){
            return 1;
        }
        return 0;
    },

    #Returns parking customdata
    getVehicleHome: func() {
        return me.home;
    },
    
    # Return GraphPosition for parking. Might return null in inconsistent groundnets;
    # Workaround for inconsistent groundnets if park pos only has one edge.
    getParkingPosition: func(parking) {
        var approach = parking.getApproach();
        var dirXY = nil;
        if (approach == nil) {
            # possible inconsistency
            #TODO consider layer if (parking.node.getEdgeCount() != 1) {
            if (parking.node.getEdgeCount() == 0) {            
                return nil;
            }
            approach = parking.node.getEdge(0);
            dirXY = approach.getEffectiveInboundDirection(parking.node);
        } else {
            dirXY = getDirectionFromHeading(parking.heading);
        }
        var position = nil;        
        if (approach.from == parking.node) {
            if (getAngleBetween(Vector3.new(dirXY.x, dirXY.y, 0), approach.getEffectiveOutboundDirection(parking.node)) < PI_2) {
                position = GraphPosition.new(approach);
            } else {
                #same position but reverse
                position = GraphPosition.new(approach, approach.getLength(), 1);
            }
        } else {
            if (getAngleBetween(Vector3.new(dirXY.x, dirXY.y, 0), approach.getEffectiveInboundDirection(parking.node)) < PI_2) {
                position = GraphPosition.new(approach, approach.getLength());
            } else {
                #same position but reverse
                position = GraphPosition.new(approach, approach.getLength(), 1);
            }
        }
        return position;
    },
        
    createPathFromGraphPosition: func(graph, from, to) {
        var layer = me.newLayer();
        var graphWeightProvider = nil;
        return createPathFromGraphPosition(graph, from, to, graphWeightProvider, SMOOTHINGRADIUS, layer, 0, MINIMUMPATHSEGMENTLEN);
    },
        
    newLayer: func() {
        layerid+=1;
        return layerid;
    },
};

var Parking = {    
	new: func(node, name, heading, pushBackRoute, radius) {	    
	    var obj = { parents: [Parking] };
		obj.node = node;
        obj.name = name;
        #in degree
        obj.heading = heading;
        obj.pushBackRoute = pushBackRoute;
        obj.radius = radius;
        obj.type = "P";
		return obj;
	},
	
	# Return edge with correct heading for reaching parkpos in defined parkpos heading.
    # This is not expected to be identical to the pushBackRoute.
    # Returns null if no such edge exists.
    getApproach: func {        
        for (var i = 0; i < me.node.getEdgeCount(); i+=1) {
            var e = me.node.getEdge(i);
            var edgeheading = getTrueHeadingFromDirection(me.node.coord,e.getEffectiveInboundDirection(me.node));
            logging.debug(""~e.getName()~" :edgeheading="~edgeheading~", parkingheading="~me.heading);
            # large rounding errors might occur, so epsilon is "large".
            #if (isEqual(me.heading, edgeheading,0.1)) {
            if (isEqual(me.heading, edgeheading,1)) {
                return e;
            }
        }
        logging.warn("no approach edge found for parking " ~ me.name);                            
        return nil;
    },                	
};

var loadGroundnet = func(path) {
    logging.debug("Looking for groundnet in "~path);
    var data = call(func io.readxml(path), nil, var err = []);
    if (size(err)){
        logging.error("Reading failed :" ~ path);
        return nil;
    }
    #data ist kein string logging.debug(data);
    #props.dump(data); # dump data
    #dump(data);
    return data;
};

logging.debug("completed Groundnet.nas");