#
#
#

logging.debug("executing Groundnet.nas");

var SMOOTHINGRADIUS = 10;
var MINIMUMPATHSEGMENTLEN = 2 * SMOOTHINGRADIUS;


var Groundnet = {
    
    new: func(projection, groundnetNode, homename) {	    
	    var obj = { parents: [Groundnet] };
		obj.groundnetgraph = Graph.new();
		#string->node
		obj.parkposname2node = {};
		obj.home = nil;
		obj.layerid = 0;
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

    findHitEdge: func(positionXYZ, heading) {
        var headinglinestartXY = Vector2.new(positionXYZ.getX(), positionXYZ.getY());
        var headinglineendXY = headinglinestartXY.add(getDirectionFromHeading(heading).multiply(8000000));
        # list of GraphEdge
        var edgelist = [];
        for (var i = 0; i < me.groundnetgraph.getEdgeCount(); i=i+1) {
            append(edgelist,me.groundnetgraph.getEdge(i));
        }
        # "best" is the nearest edge
        var best = nil;
        var bestintersection = nil;
        var bestdistance = FloatMAX_VALUE;
        foreach (var e ; edgelist) {
            if (e.getLayer() == 0) {
                var linestartXY = Vector2.new(e.getFrom().getLocation().getX(), e.getFrom().getLocation().getY());
                var lineendXY = Vector2.new(e.getTo().getLocation().getX(), e.getTo().getLocation().getY());
                var intersectionXY = getLineIntersection(headinglinestartXY, headinglineendXY, linestartXY, lineendXY);
                if (intersectionXY != nil and isPointOnLine(linestartXY, lineendXY, intersectionXY)) {
                    var distance = getDistanceXYZ(positionXYZ, Vector3.new(intersectionXY.getX(), intersectionXY.getY(), 0));
                    #logger.debug("intersection=" + intersection + " with " + e.getName() + ", distance=" + distance);
                    var angle = getAngleBetween(Vector3.new(intersectionXY.getX(), intersectionXY.getY(), 0).subtract(positionXYZ), buildFromVector2(getDirectionFromHeading(heading)));
                    if (angle < PI_2) {
                        if (!empty(e.getName()) and distance < bestdistance) {
                            best = e;
                            bestintersection = intersectionXY;
                            bestdistance = distance;
                        }
                    }
                }
            }
        }
        if (best == nil) {
            return nil;
        }
        return [best, bestintersection];
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
        
    createPathFromGraphPosition: func(from, to,  graphWeightProvider = nil, withsmooth = 1, layer = -300000) {
        if (layer == -300000){
            layer = me.newLayer();
        }
        return createPathFromGraphPosition(me.groundnetgraph, from, to, graphWeightProvider, SMOOTHINGRADIUS, layer, withsmooth, MINIMUMPATHSEGMENTLEN);
    },
        
    newLayer: func() {
        me.layerid+=1;
        #logging.debug("new layer is "~layerid);
        return me.layerid;
    },
    
    # Create approach to aircraft door.
    #
    # layerid is created internally and the same for all created segements.
    # Returns [edge at door],[returnsuccessor].
    createDoorApproach: func( worlddoorposXY, aircraftdirectionXY, worldwingpassingpointXY, worldrearpointXY, wingspread) {
        var layer = me.newLayer();
        #heading away from aircraft
        var approachdirectionXY = aircraftdirectionXY.rotate(-90);
        var approachlen = MINIMUMPATHSEGMENTLEN + 0.001;
        approachlen = wingspread / 4;
        var doorposXYZ = buildFromVector2(worlddoorposXY);
        var door0 = me.groundnetgraph.addNode("door0", doorposXYZ);
        var door1 = me.groundnetgraph.addNode("door1", doorposXYZ.add(buildFromVector2(approachdirectionXY).normalize().multiply(approachlen)));

        var dooredge = me.groundnetgraph.connectNodes(door0, door1, "",layer);

        var wing0 = me.groundnetgraph.addNode("wing0", buildFromVector2(worldwingpassingpointXY));
        var door2wing = me.groundnetgraph.connectNodes(door1, wing0, "door2wing", layer);

        # direction at wing edge
        var wingdirectionXY = approachdirectionXY.rotate(-90);
        var wing1 = me.groundnetgraph.addNode("wing1", wing0.getLocation().add(buildFromVector2(wingdirectionXY).normalize().multiply(approachlen)));
        var c1 = me.groundnetgraph.connectNodes(wing0, wing1, "wingedge", layer);

        #default branch/merge node is first node if no specific node can be found.
        var branchnode = me.groundnetgraph.getNode(0);
        var o = me.findHitEdge(wing1.getLocation(), getHeadingFromDirection(wingdirectionXY));
        var best = nil;
        if (o != nil) {
            best =  o[0];
            var distanceoffrom = getDistanceXYZ(best.from.getLocation(), buildFromVector2(worldrearpointXY));
            var distanceofto = getDistanceXYZ(best.to.getLocation(), buildFromVector2(worldrearpointXY));
            if (distanceoffrom < distanceofto) {
                branchnode = best.from;
            } else {
                branchnode = best.to;
            }
        }
        var c2 = me.groundnetgraph.connectNodes(wing1, branchnode, "branchedge", layer);
        return [dooredge, door2wing];
    },

    # Create approach to aircraft wing for refueling.
    #
    # layerid is created internally and the same for all created segements.
    # Returns [edge at wing],[returnsuccessor].
    createFuelingApproach: func(aircraftpositionXYZ, aircraftdirectionXY, worldleftwingapproachpointXY, worldrearpointXY) {
        var layer = me.newLayer();
        #heading appx parallel to wing of aircraft
        var approachdirectionXY = aircraftdirectionXY.rotate(110);
        var approachlen = MINIMUMPATHSEGMENTLEN + 0.001;
        var innerposXYZ = buildFromVector2(worldleftwingapproachpointXY);
        var innernode = me.groundnetgraph.addNode("innernode", innerposXYZ);
        var outernode = me.groundnetgraph.addNode("outernode", innerposXYZ.add(buildFromVector2(approachdirectionXY).normalize().multiply(approachlen)));
        var wingedge = me.groundnetgraph.connectNodes(innernode, outernode, "wingedge", layer);

        var approachbegin = me.groundnetgraph.addNode("enternode", innerposXYZ.subtract(buildFromVector2(aircraftdirectionXY).normalize().multiply(30)));
        var approach = me.groundnetgraph.connectNodes(approachbegin, innernode, "wingapproach", layer);

        #default merge/branch node is first node if no specific node can be found.
        var branchnode = me.groundnetgraph.getNode(0);
        var o = me.findHitEdge(approachbegin.getLocation(), getHeadingFromDirection(aircraftdirectionXY.negate()));
        var best = nil;
        if (o != nil) {
            best = o[0];
            var distanceoffrom = getDistanceXYZ(best.from.getLocation(), buildFromVector2(worldrearpointXY));
            var distanceofto = getDistanceXYZ(best.to.getLocation(), buildFromVector2(worldrearpointXY));
            if (distanceoffrom < distanceofto) {
                branchnode = best.from;
            } else {
                branchnode = best.to;
            }
        }

        var branchedge = me.groundnetgraph.connectNodes(branchnode, approachbegin, "branchedge", layer);
        return [wingedge, approach, branchedge];
    },
 
    # name is "create" instead of "find" because a temporary arc is added.
    createBack: func( startnode,  dooredge,  successor) {
        var layer = me.newLayer();
        var turn = createBack(me.groundnetgraph, startnode, dooredge, successor, layer);
        return turn;
    },
    
    createWingReturn: func(wingedge, wingbranchedge, aircraftdirectionXY) {
        var layer = me.newLayer();
        var return0 = extendWithEdge(me.groundnetgraph, wingedge, SMOOTHINGRADIUS + 0.001, layer);
        logging.debug("return0.layer="~return0.getLayer()~" "~layer);
        return0.setName("return0");
        var return1 = extend(me.groundnetgraph, return0.to, buildFromVector2(aircraftdirectionXY.negate()), MINIMUMPATHSEGMENTLEN, layer);
        return1.setName("return1");
        var nearest = me.groundnetgraph.findNearestNode(return1.to.getLocation(), NodeToLayer0Filter());

        var return2 = me.groundnetgraph.connectNodes(return1.to, nearest, "return12", layer);
        return return0;
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
    logging.debug("Loading groundnet from "~path);
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

# Search FG_SCENERY path for groundnet.xml
var findGroundnetXml = func(relpath) {
    foreach (var scenery_node;props.globals.getNode("/sim").getChildren("fg-scenery")) {
        var scenerypath = scenery_node.getValue();
        logging.debug("Looking for "~relpath~" in "~scenerypath);
        var fullpath = scenerypath ~ "/" ~ relpath;
        if (io.stat(fullpath) != nil) {
            return fullpath;
        }
    }
    return nil;
};                  
     
# Returns XY world coordinates for aircraft local coordinates.
var getAircraftWorldLocation = func( aircraftpositionXYZ,  heading,  aircraftlocalXYZ) {
    var aircraftlocalXY = Vector2.new(aircraftlocalXYZ.x,aircraftlocalXYZ.y);
    #var direction = getDirectionFromHeading(heading);
    var degree = getDegreeFromHeading(heading);
    aircraftlocalXY = aircraftlocalXY.rotate(degree);

    var worlddoorpos = aircraftpositionXYZ.add(buildFromVector2(aircraftlocalXY));
    return Vector2.new(worlddoorpos.getX(), worlddoorpos.getY());
};

# a GraphNodeFilter
var NodeToLayer0Filter = func() {
    return {acceptNode :func (n) {
        for (var i = 0; i < n.getEdgeCount(); i=i+1) {
            if (n.getEdge(i).getLayer() == 0) {
                return 1;
            }
        }
        return 0;
    }};
};
           
logging.debug("completed Groundnet.nas");