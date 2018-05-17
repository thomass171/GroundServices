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
        delete(servicepoints,me.node.getValue("id"));
        me.node.remove();                
    },
	                	
};

# abstract class
var ScheduledAction = {    
	new: func() {	    
	    var obj = { parents: [ScheduledAction] };
	    return obj;
	},
	
	initActionNode: func(schedulenode, name) {
	    me.node = schedulenode.addChild("action");
	    me.node.getNode("name",1).setValue(name);
	    me.node.getNode("triggertimestamp",1).setValue(0);
	    #1=active,2=completed,3=failed
        me.node.getNode("state",1).setValue(0);
	},
	
	trigger: func(){
        me.dotrigger();
        if (me.getState()==1) {            
            me.node.getNode("triggertimestamp",1).setValue(systime());
        }
    },
    
    isActive: func() {
        return me.getState() == 1;
    },
    
    checkCompletion: func() {
        if (me.getState() == 2 or me.getState() == 3) {
            #already checked
            return 1;
        }
        if (me.doCheckCompletion()) {
            me.setState(2);
            return 1;
        }
        return 0;
    },

    getState: func() {
        return getChildNodeValue(me.node,"state",0);
    },
    
    setState: func(state) {
        me.node.getNode("state",1).setValue(state);
    },
};

var VehicleOrderAction = {    
    new: func(schedule, vehicletype, destination) {	    
	    var obj = { parents: [VehicleOrderAction, ScheduledAction.new()] };
	    obj.schedule = schedule;
		obj.vehicletype = vehicletype;
		# destination is a GraphNode
        obj.destination = destination;
        obj.initActionNode(schedule.node,"VehicleOrderAction");
        return obj;
	},		
	
	# A currently moving vehicle cannot be relocted for now because it most likely runs on a temporary unknown layer (-> "no path found");
    dotrigger: func() {
        var vlist = findAvailableVehicles(me.vehicletype);
        if (size(vlist) == 0) {
            logging.warn("VehicleOrderAction: no available vehicle found for type "~me.vehicletype);
            return;
        }
        me.schedule.vehicle = vlist[0];
        me.setState(1);
        var vhc = me.schedule.vehicle.vhc;
        var gmc = me.schedule.vehicle.gmc;
       
        var groundnet = me.schedule.groundnet;
        var start = gmc.currentposition;
        var approach = nil;
        if (me.schedule.servicepoint == nil){
            approach = groundnet.createPathFromGraphPosition( start,me.destination);
        } else{
            approach = me.schedule.servicepoint.getApproach(start, me.destination,1);
        }

        if (approach != nil) {
           #
        } else {
            logging.error("no approach found to " ~ me.destination.toString());
            #set to failed.
            me.state=3;
            return;
        }
        vhc.schedule = me.schedule;
        logging.debug("set approachpath:" ~ approach.toString());
        gmc.setPath(approach);
        if (me.vehicletype == "fueltruck") {
            # avoid driving catering and fueltruck alongside by a 6 second delay
            me.schedule.vehicle.delay = 6;
        }
    },

    # only called for states 0 and 1.
    doCheckCompletion: func() {
        if (me.schedule.vehicle == nil) {
            #not yet started
            return 0;
        }
        if (me.schedule.vehicle.gmc.pathCompleted()) {
            logging.debug("VehicleOrderAction completed");
            return 1;
        }
        return 0;
    },
                	
};

var VehicleServiceAction = {    
	new: func(schedule,intervalinseconds) {	    
	    var obj = { parents: [VehicleServiceAction, ScheduledAction.new()] };
	    obj.schedule = schedule;
	    # duration in seconds
		obj.interval = intervalinseconds;
        obj.initActionNode(schedule.node,"VehicleServiceAction");
        return obj;
	},
	
    dotrigger: func() {
        me.setState(1);
    },	
    
    doCheckCompletion: func() {
        if (systime() - me.node.getNode("triggertimestamp",1).getValue() > me.interval) {
            logging.debug("VehicleServiceAction completed");
            return 1;
        }
        return 0;
    },   	
};

var VehicleReturnAction = {    
	new: func(schedule, startbackwards, sp, fordoor) {	    
	    var obj = { parents: [VehicleReturnAction, ScheduledAction.new()] };
	    obj.schedule = schedule;
	    obj.startbackwards = startbackwards;
	    obj.sp = sp;
	    obj.fordoor = fordoor;
	    obj.released = 0;
        obj.initActionNode(schedule.node,"VehicleReturnAction");
        return obj;
	},
	
    dotrigger: func() {
        me.setState(1);
        var returnpath = nil;
        if (me.fordoor) {
            returnpath = me.sp.getDoorReturnPath(1);
        } else {
            returnpath = me.sp.getWingReturnPath(1);
        }
        
        if (returnpath != nil) {
            # nothing?
        } else {
            logging.error("no returnpath found");
            #TODO state?
            return;
        }
        var gmc = me.schedule.vehicle.gmc;
        gmc.setPath(returnpath);        
    },	
    
    doCheckCompletion: func() {
        if (me.schedule.vehicle == nil) {
            #not yet started
            return 0;
        }
        if (me.schedule.vehicle.gmc.pathCompleted()) {
            # Avoid accidentally double release
            if (!me.released){
                me.schedule.vehicle.vhc.schedule=nil;
                me.released=1;
            }
            logging.debug("VehicleReturnAction completed");
            return 1;
        }
        return 0;
    },   	
};

var scheduleid = 1;

var Schedule = {    
	new: func(servicepoint, groundnet) {	    
	    var obj = { parents: [Schedule] };
	    logging.info("Creating Schedule "~scheduleid);
		obj.servicepoint = servicepoint;
        obj.groundnet = groundnet;
        obj.actions = [];
        obj.node = schedulesN.addChild("schedule");
        #schedule itself has no position
        #obj.node.getNode("position/latitude-deg", 1).setValue(obj.servicepoint.aa.coord.lat());
        #obj.node.getNode("position/longitude-deg", 1).setValue(obj.servicepoint.aa.coord.lon());
        obj.node.getNode("id",1).setValue(scheduleid);
        obj.id = scheduleid;
        obj.completed = 0;      
        scheduleid += 1;
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
            #
            if (a.getState() == 0 and (predecessor == nil or predecessor.getState() == 2)) {
                logging.debug("found next action in "~me.getId()~" , state is "~a.getState());
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
            if (a.getState() == 3) {
                #terminateduetofailure
                me.completed = 1;
                    return 1;
            }
            if (a.getState() != 2) {
                return 0;
            }
        }
        me.completed = 1;
        return 1;
    },
  
    isCompleted: func() {
          return me.completed;
    },
    
    toString: func() {
          return "schedule "~me.id;
    },
	
    getId: func() {
        return getChildNodeValue(me.node,"id",0);
    },
    
    delete: func() {
        delete(schedules,me.id);
        me.node.remove();
    },               	
};

var getAircraftConfiguration = func(type) {
    var node738 = nil;
    foreach (var aircraft_node;simaigroundservicesN.getChildren("aircraft")){
        if (getChildNodeValue(aircraft_node,"type","") == type) {
            logging.debug("found aircraft type "~type);        
            return GroundServiceAircraftConfig.new (aircraft_node);
        }
        if (getChildNodeValue(aircraft_node,"type","") == "738") {
            node738 = aircraft_node;
        }    
    }
    logging.debug("aircraft type "~type~" not found.");
    if (node738 != nil) {                        
        logging.debug("Using 738 as default.");
        return GroundServiceAircraftConfig.new (node738);
    }
    logging.error("no default aircraft 738 found.");                                
    return nil;
}

var addSchedule = func(s) {
    # node is created in class Schedule
    schedules[s.id] = s;        
};

logging.debug("completed GroundService.nas");