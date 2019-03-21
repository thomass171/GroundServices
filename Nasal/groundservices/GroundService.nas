#
#
#

logging.debug("executing GroundService.nas");

var GroundServiceAircraftConfig = {    
	new: func( aircraftN) {	    
	    var obj = { parents: [GroundServiceAircraftConfig] };
	    obj.aircraftN = aircraftN;
	    obj.wingspread = getChildNodeValue(aircraftN,"wingspread",22);
        return obj;
	},
	
    getCateringDoorPosition: func() {
        var doorN = me.aircraftN.getChildren("door")[0];
        return Vector3.new(getChildNodeValue(doorN,"x",0), -getChildNodeValue(doorN,"y",0), getChildNodeValue(doorN,"z",0));
    },

    getWingPassingPoint: func() {
        var wingpassingpointN = me.aircraftN.getChildren("wingpassingpoint")[0];            
        return Vector3.new(getChildNodeValue(wingpassingpointN,"x",0), getChildNodeValue(wingpassingpointN,"y",0),0);
    },

    getLeftWingApproachPoint: func() {
        var leftwingapproachpointN = me.aircraftN.getChildren("leftwingapproachpoint")[0];            
        return Vector3.new(getChildNodeValue(leftwingapproachpointN,"x",0), getChildNodeValue(leftwingapproachpointN,"y",0),0);
    },

    # point appx. 5 meter behind the aircraft
    getRearPoint: func() {
        var xoffset = 28;
        var p = Vector3.new(xoffset, 0 , 0);
        return p;
    },		                	
};

var servicepointid = 1;

#
# <aircraft> is GroundServiceAircraftConfig
# <aa> is arrivedaircraft
# All coordinates here are projected graph coordinates! So the phrase "world" is confusing."world"->"prj"
#
var ServicePoint = {    
	new: func(groundnet, aa, prjpositionXYZ, heading, aircraft) {	    
	    var obj = { parents: [ServicePoint] };
	    logging.info("Creating ServicePoint "~servicepointid~" for type "~aa.type~",position="~prjpositionXYZ.toString()~",heading="~heading);
                        
		obj.groundnet = groundnet;
        obj.aa = aa;
        obj.prjpositionXYZ = prjpositionXYZ;
        obj.heading = heading;
        obj.aircraft = aircraft;
        obj.directionXY = getDirectionFromHeading(heading);
        obj.node = servicepointsN.addChild("servicepoint");
        obj.node.getNode("position/latitude-deg", 1).setValue(aa.coord.lat());
        obj.node.getNode("position/longitude-deg", 1).setValue(aa.coord.lon());
        obj.node.getNode("id",1).setValue(servicepointid);
        servicepointid += 1;
        
        #Create points/steps for reaching front right door
        var doorpos = aircraft.getCateringDoorPosition();
        obj.prjdoorpos = groundnet.getProjectedAircraftLocation(prjpositionXYZ, heading, doorpos);
        var wingpos = aircraft.getWingPassingPoint();
        obj.prjwingpassingpoint = groundnet.getProjectedAircraftLocation(prjpositionXYZ, heading, wingpos);
        obj.prjdoorturncenter = groundnet.getProjectedAircraftLocation(prjpositionXYZ, heading, doorpos.add(Vector3.new(-SMOOTHINGRADIUS, 0, 0)));
        obj.prjdoorturnpoint = groundnet.getProjectedAircraftLocation(prjpositionXYZ, heading, doorpos.add(Vector3.new(-SMOOTHINGRADIUS, SMOOTHINGRADIUS, 0)));

        # Create points/steps for reaching back area of left wing for fuel truck
        obj.prjleftwingapproachpoint = groundnet.getProjectedAircraftLocation(prjpositionXYZ, heading, aircraft.getLeftWingApproachPoint());
        obj.prjrearpoint = groundnet.getProjectedAircraftLocation(prjpositionXYZ, heading, aircraft.getRearPoint());
        obj.buildHelperPaths();
        
        aa.receivingservice = 1;
        
        
        return obj;
	},
		
    buildHelperPaths: func() {
        # path to door
        var e = me.groundnet.createDoorApproach(me.prjdoorpos, me.directionXY, me.prjwingpassingpoint, me.prjrearpoint, me.aircraft.wingspread,approachoffsetNode.getValue());
        me.doorEdge = e[0];
        me.door2wing = e[1];
        me.doorbranchedge = e[2];
        me.backturn = me.groundnet.createBack(me.doorEdge.from, me.doorEdge, me.door2wing);
        
        # path to left wing. Used for fuel truck. Might be to small depending on aircraft.
        e = me.groundnet.createFuelingApproach(me.prjpositionXYZ, me.directionXY, me.prjleftwingapproachpoint, me.prjrearpoint);
        me.wingedge = e[0];
        me.wingapproach = e[1];
        me.wingbranchedge = e[2];
        me.wingbestHitEdge = e[3];
        e = me.createWingReturn();
        me.wingreturn = e[0];
        me.wingreturn1 = e[1];
        me.wingreturn2 = e[2];
    },
    
    # Find path to a servicepoint node.
    getApproach: func( start,  destination,  withsmooth) {
        var graphWeightProvider = DefaultGraphWeightProvider.new(me.groundnet.groundnetgraph, 0);
        append(graphWeightProvider.validlayer,me.doorEdge.getLayer());
        append(graphWeightProvider.validlayer,me.wingedge.getLayer());
        me.voidEdgeUnderAircraft(graphWeightProvider);
        var approach = me.groundnet.createPathFromGraphPosition(start, destination, graphWeightProvider, withsmooth);
        #me.groundnet.groundnetgraph.dumpToLog();
        if (approach != nil) {
            approach.validateAltitude();
        }
        return approach;
    },

    # Avoid edges under the aircraft. Nearest will probably find the edge to parking pos.
    # should be optimized.
    voidEdgeUnderAircraft: func( graphWeightProvider) {
        var nearest = me.groundnet.groundnetgraph.findNearestNode(me.prjpositionXYZ, nil);
        for (var i = 0; i < nearest.getEdgeCount(); i = i+1) {
            var e = nearest.getEdge(i);
            # don't accidenttally ignore temporary approach edges.
            if (e.getLayer() == 0) {
                append(graphWeightProvider.voidedges,e);
            }
        }
    },

    # Return home from door. With backmove.
    getDoorReturnPath: func( withsmooth) {
        var graphWeightProvider = me.getDoorReturnPathProvider();
        var returnpath = me.groundnet.createBackPathFromGraphPosition(me.doorEdge.from, me.doorEdge, me.backturn, 
            me.groundnet.getVehicleHome().node, graphWeightProvider, withsmooth, nil);
        return returnpath;
    },

    getDoorReturnPathProvider: func() {
        var graphWeightProvider = DefaultGraphWeightProvider.new(me.groundnet.groundnetgraph, 0);
        append(graphWeightProvider.validlayer,me.backturn.getLayer());
        append(graphWeightProvider.validlayer,me.doorEdge.getLayer());
        me.voidEdgeUnderAircraft(graphWeightProvider);
        return graphWeightProvider;
    },

    getWingReturnPath: func( withsmooth) {
        var graphWeightProvider = DefaultGraphWeightProvider.new(me.groundnet.groundnetgraph, 0);
        append(graphWeightProvider.validlayer,me.wingreturn.getLayer());
        logging.debug("wingreturnlayer="~me.wingreturn.getLayer());
        #me.voidEdgeUnderAircraft(graphWeightProvider);
        var returnpath = me.groundnet.createPathFromGraphPosition(GraphPosition.new(me.wingedge), me.groundnet.getVehicleHome().node, 
            graphWeightProvider, withsmooth);
        return returnpath;
    },

    getLayer: func() {
        return [me.backturn.getLayer(), me.doorEdge.getLayer(), me.wingedge.getLayer(), me.wingreturn.getLayer()];
    },

    createWingReturn: func() {
        var e = me.groundnet.createWingReturn(me.wingedge, me.wingbranchedge, me.directionXY);
        return e;
    },

    delete: func() {
        logging.debug("deleting ServicePoint "~me.node.getValue("id"));
        foreach (var layerid ; me.getLayer()) {
            me.groundnet.groundnetgraph.removeLayer(layerid);
        }
        # remove myself from global list
        delete(servicepoints,me.node.getValue("id"));
        me.node.remove();                
    },
	                	
};

# A currently moving vehicle cannot be relocted for now because it most likely runs on a temporary unknown layer (-> "no path found");
launchServiceVehicle = func(modeltype, groundnet, servicepoint,servicedurationinseconds) {
    var vlist = findAvailableVehicles(VEHICLE_CAR,modeltype);
    if (size(vlist) == 0) {
        logging.warn("launchServiceVehicle: no available service vehicle found for type " ~ modeltype);
        servicepoint.delete();
        return;
    }
    var vehicle = vlist[0];
    var vhc = vehicle.vhc;
    var gmc = vehicle.gmc;
    var gsc = vehicle.gsc;

    var destination = gsc.setStateApproaching(servicepoint,modeltype,servicedurationinseconds);
    var start = gmc.currentposition;
    var approach = nil;
    if (servicepoint == nil){
        approach = groundnet.createPathFromGraphPosition( start,destination);
    } else{
        approach = servicepoint.getApproach(start, destination,1);
    }

    if (approach != nil) {
        #
    } else {
        logging.error("no approach found to " ~ destination.toString());
        gsc.reset();
        return;
    }
    logging.debug("set approachpath:" ~ approach.toString());
    gmc.setPath(approach);
    if (modeltype == VEHICLE_FUELTRUCK) {
        # avoid driving catering and fueltruck alongside by a 6 second delay
        vehicle.delay = 6;
    }
}

returnVehicle = func(vehicle, gsc) {
    var returnpath = nil;
    logger.debug("return vehicle from service point " ~ gsc.sp.node.getValue("id") ~ ". fordoor=" ~ gsc.fordoor);

    if (gsc.fordoor) {
        returnpath = gsc.sp.getDoorReturnPath(1);
    } else {
        returnpath = gsc.sp.getWingReturnPath(1);
    }
        
    if (returnpath != nil) {
        # nothing?
    } else {
        logging.error("no returnpath found");
        return;
    }
    var gmc = vehicle.gmc;
    gmc.setPath(returnpath);
    gsc.setStateIdle();
}

var getAircraftConfiguration = func(type) {
    var node738 = nil;
    foreach (var aircraft_node;simaigroundservicesN.getChildren("aircraft")){
        var acceptedtypes = split(",",getChildNodeValue(aircraft_node,"type",""));
        foreach (var acceptedtype; acceptedtypes) {
            # Bug in match(?). Append XX as workaround
            if (string.match(type~"XX",acceptedtype)) {
                logging.debug("found aircraft type " ~ acceptedtype ~ " for " ~ type);        
                return GroundServiceAircraftConfig.new (aircraft_node);
            }        
            if (acceptedtype == "738*") {
                node738 = aircraft_node;
            }
        }    
    }
    logging.warn("aircraft type "~type~" not found.");
    if (node738 != nil) {                        
        logging.debug("Using 738 as default.");
        return GroundServiceAircraftConfig.new (node738);
    }
    logging.error("no default aircraft 738 found.");                                
    return nil;
}

logging.debug("completed GroundService.nas");