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

#
# <aircraft> is GroundServiceAircraftConfig
#       
var ServicePoint = {    
	new: func(groundnet, aa, positionXYZ, heading, aircraft) {	    
	    var obj = { parents: [ServicePoint] };
		obj.groundnet = groundnet;
        obj.aa = aa;
        obj.positionXYZ = positionXYZ;
        obj.heading = heading;
        obj.aircraft = aircraft;
        
        obj.directionXY = getDirectionFromHeading(heading);

        #Create points/steps for reaching front right door
        var doorpos = aircraft.getCateringDoorPosition();
        var worlddoorpos2 = getAircraftWorldLocation(positionXYZ, heading, doorpos);
        #addGroundMarker(worlddoorpos.getX(), worlddoorpos.getY());
        #z Wert?
        obj.worlddoorpos = buildFromVector2(worlddoorpos2);
        var wingpos = aircraft.getWingPassingPoint();
        obj.worldwingpassingpoint = getAircraftWorldLocation(positionXYZ, heading, wingpos);
        obj.worlddoorturncenter = getAircraftWorldLocation(positionXYZ, heading, doorpos.add(Vector3.new(-SMOOTHINGRADIUS, 0, 0)));
        obj.worlddoorturnpoint = getAircraftWorldLocation(positionXYZ, heading, doorpos.add(Vector3.new(-SMOOTHINGRADIUS, SMOOTHINGRADIUS, 0)));

        # Create points/steps for reaching back area of left wing for fuel truck
        obj.worldleftwingapproachpoint = getAircraftWorldLocation(positionXYZ, heading, aircraft.getLeftWingApproachPoint());
        obj.worldrearpoint = getAircraftWorldLocation(positionXYZ, heading, aircraft.getRearPoint());
        obj.buildHelperPaths();
        return obj;
	},
	
    buildHelperPaths: func() {
        # path to door
        var e = me.groundnet.createDoorApproach(Vector2.new(me.worlddoorpos.getX(), me.worlddoorpos.getY()), me.directionXY, 
            me.worldwingpassingpoint, me.worldrearpoint, me.aircraft.wingspread);
        me.doorEdge = e[0];
        me.door2wing = e[1];
        me.backturn = me.groundnet.createBack(me.doorEdge.from, me.doorEdge, me.door2wing);
        
        # path to left wing. Used for fuel truck. Might be to small depending on aircraft.
        e = me.groundnet.createFuelingApproach(me.positionXYZ, me.directionXY, me.worldleftwingapproachpoint, me.worldrearpoint);
        me.wingedge = e[0];
        me.wingapproach = e[1];
        me.wingbranchedge = e[2];
        me.wingreturn = me.createWingReturn();
    },
    
    # Find path to a servicepoint node.
    getApproach: func( start,  destination) {
        return getApproach(start, destination, 1);
    },

    #
    getApproach: func( start,  destination,  withsmooth) {
        var graphWeightProvider = DefaultGraphWeightProvider.new(me.groundnet.groundnetgraph, 0);
        append(graphWeightProvider.validlayer,me.doorEdge.getLayer());
        append(graphWeightProvider.validlayer,me.wingedge.getLayer());
        me.voidEdgeUnderAircraft(graphWeightProvider);
        var approach = me.groundnet.createPathFromGraphPosition(start, destination, graphWeightProvider, withsmooth);
        return approach;
    },

    # Avoid edges under the aircraft. Nearest will probably find the edge to parking pos.
    # should be optimized.
    voidEdgeUnderAircraft: func( graphWeightProvider) {
        var nearest = me.groundnet.groundnetgraph.findNearestNode(me.positionXYZ, nil);
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
            me.groundnet.getVehicleHome().node, graphWeightProvider, withsmooth);
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

    close: func() {
        foreach (var layerid ; getLayer()) {
            me.groundnet.groundnetgraph.removeLayer(layerid);
        }
    },
	                	
};

# abstract class
var ScheduledAction = {    
	new: func() {	    
	    var obj = { parents: [ScheduledAction] };
	    #1=active,2=completed,3=failed
        obj.state = 0;
        obj.triggertimestamp = 0;
		return obj;
	},		                	
};

var VehicleOrderAction = {    
	new: func(schedule, vehicletype, destination) {	    
	    var obj = nil;#{ parents: [VehicleOrderAction, ScheduledAction] };
	    obj.schedule = schedule;
		obj.vehicletype = vehicletype;
        obj.destination = destination;
        return obj;
	},		
	
	# A currently moving vehicle cannot be relocted for now because it most likely runs on a temporary unknown layer (-> "no path found");
    dotrigger: func() {
       me.schedule.vehicle = TrafficSystem.findAvailableVehicle(me.vehicletype);
       if (me.schedule.vehicle == nil) {
           return;
       }

       me.state = 1;
       var vc = getVehicleComponent(me.schedule.vehicle);
       var gmc = getGraphMovingComponent(me.schedule.vehicle);
       
       var groundnet = me.schedule.groundnet;
       var start = groundnet.getParkingPosition(groundnet.getParkPos("B_8"));
       start = gmc.currentposition;
       var approach = nil;
       if (me.schedule.servicepoint == nil){
           approach = groundnet.createPathFromGraphPosition( start,me.destination);
       } else{
           approach = me.schedule.servicepoint.getApproach(start, me.destination);
       }

       if (approach != nil) {
           #
       } else {
           logging.error("no approach found to " ~ me.destination);
           #set to failed.
           me.state=3;
           return;
       }
       vc.schedule = me.schedule;
       logging.debug("set approachpath:" ~ approach.toString());
       gmc.setPath(approach);
   },

   # only called for states 0 and 1.
   doCheckCompletion: func() {
       if (me.schedule.vehicle == nil) {
           #not yet started
           return 0;
       }
       if (getGraphMovingComponent(me.schedule.vehicle).pathCompleted()) {
           return 1;
       }
       return 0;
   },
                	
};

var Schedule = {    
	new: func(servicepoint, groundnet) {	    
	    var obj = { parents: [Schedule] };
		obj.servicepoint = servicepoint;
        obj.groundnet = groundnet;
        obj.actions = [];
        return obj;
	},
	
	# find first not active Action. But only if predecessor is no longer active
    # TODO timestamp 
    next: func () {
        var predecessor = nil;
        for (var i = 0; i < size(me.actions); i=i+1) {
            var a = me.actions[i];
            if (i > 0) {
                predecessor = me.actions[i - 1];
            }
            if (a.state == 0 and (predecessor == nil or predecessor.state == 2)) {
                return a;
            }
        }
        return nil;
    },
          
    addAction: func(action) {
        append(me.actions,action);
    },
          
    checkCompletion: func() {
        foreach(var a; me.actions) {                  
            if (a.state == 3) {
                #terminateduetofailure
                me.servicepoint = nil;
                    return 1;
            }
            if (a.state != 2) {
                return 0;
            }
        }
        servicepoint = nil;
        return 1;
    },
  
    toString: func() {
          return " for sp?";
    },
	                	
};

var getAircraftConfiguration = func(type) {
    foreach (var aircraft_node;simaigroundservicesN.getChildren("aircraft")){
        if (getChildNodeValue(aircraft_node,"type","") == type) {
            logging.debug("found aircraft type "~type);        
            return GroundServiceAircraftConfig.new (aircraft_node);
        }    
    }
    logging.debug("aircraft type "~type~" not found");                        
    return nil;
}

logging.debug("completed GroundService.nas");