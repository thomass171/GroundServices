#
# 
#

logging.debug("executing main.nas");

#--------------------------------------------------------------------------------------------------

var showTestMessage = func(msg) {
    logging.debug(msg);
	gui.popupTip("Graph Test Message: " ~ msg);
}

#root path of addon
var root = nil;
var fgroot = nil;

var oclock = func(bearing) int(0.5 + geo.normdeg(bearing) / 30) or 12;
var airportelevation = 0;


var tanker_msg = func setprop("sim/messages/ai-plane", call(sprintf, arg));
var pilot_msg = func setprop("/sim/messages/pilot", call(sprintf, arg));
var atc_msg = func setprop("sim/messages/atc", call(sprintf, arg));

var basepos =  geo.Coord.new().set_latlon(50.883056,7.116523,400);
var groundnet = nil;
# center coord of current airport, otherwise nil
var center = nil;

var refmarkermodel = nil;
var projection = nil;
var lastcheckforstandby = 0;
var lastcheckforaircraft = 0;
var last120 = 0;
var lastscheduling = 0;
var checkforaircraftinterval = 15;
var schedulinginterval = 2;

# Nodes
var visualizegroundnetNode = nil;
var statusNode = nil;
# current/next/near airport
var airportNode = nil;
var automoveNode = nil;
var scalefactorNode = nil;
var approachoffsetNode = nil;
var fuelingdurationNode = nil;
var cateringdurationNode = nil;
var maxservicepointsNode = nil;
var simaigroundservicesN = nil;
var autoserviceNode = nil;
var schedulesN = nil;
var servicepointsN = nil;
var maprangeNode = nil;

#increased for avoiding vehicles that are blocked due to missing escape path (eg. missing teardrop turn) to waste CPU time
#increased to 60 for having more vehicles ready for service
var maxidletime = 60;
var failedairports = {};
var minairportrange = 3;
var homename = nil;
var destinationlist = nil;
#hash of service points (id is key)
var servicepoints = {};
#hash of active schedules (id is key)
var schedules = {};
var scenario = 1;
var scalefactor = 1;
var maxservicepoints = 1;
var activetimestamp = 0;
var collectradius = 500;
var false = 0;
var true = 1;

var report = func {
    #atc_msg("Ground Service Status: "~statusNode.getValue());
    foreach (var v; values(GroundVehicle.active))
	    v.report();
}



# also used for checking for departure. Doesn't change the
# current state.
var findAirport = func() {
    var apts = findAirportsWithinRange(minairportrange);
    var s = "";
    var foundairport = nil;
    foreach(var apt; apts){
        s ~= sprintf("%s (%s),", apt.name, apt.id);
        if ( foundairport == nil) {
            if (contains(failedairports,apt.id)){
                logging.warn("Ignoring previously failed airport " ~ apt.id);
            } else {
                foundairport = apt.id;
            }
        }
    }
    if (foundairport == nil) {
        logging.debug("no airport found");                    
        return nil;
    }
    logging.debug("Airports within "~minairportrange~" nm: " ~ s);    
    return foundairport;
}
#
# when an airport is found, icao will be set as indicator.
# Return 1 when an airport was found, otherwise 0
var getAirportInfo = func() {
    var s = "";
    airportNode.setValue("");
    var icao = findAirport();        
    if (icao == nil) {                   
        return 0;
    }
    airportNode.setValue(icao);
    var info = airportinfo(airportNode.getValue());
    logging.debug("Found airport " ~ info.name ~ " (" ~ info.id ~ ",lat/lon=" ~info.lat ~ ";" ~ info.lon ~ ",ele=" ~info.elevation ~ " m)");
    center = geo.Coord.new().set_latlon(info.lat,info.lon).set_alt(info.elevation);
    airportelevation = info.elevation;
    logging.debug("center: lat=" ~ center.lat() ~ ",lon=" ~ center.lon());
        	
    #foreach(var rwy; keys(info.runways)){
    #    logging.debug(sprintf(rwy, ": ", math.round(info.runways[rwy].length * M2FT), " ft (", info.runways[rwy].length, " m)"));
    #}
    return 1;
}

var getCurrentAirportIcao = func() {
    if (airportNode != nil) {
        return airportNode.getValue();
    }
    return "";
}

#
# Create an additional ground vehicle based on a given /sim/ai/groundservices/vehicle property node.
# has index parameter to be callable by dialogs.
# When no position is supplied, the vehicle is located at the groundnets home position (except aircrafts), which might be defined in groundservices.xml.
#
var createVehicle = func(sim_ai_index, graphposition=nil, delay=0) {
    logging.debug("createVehicle "~sim_ai_index~ " with delay " ~ delay);
    course=0;
    vehicle_node = props.globals.getNode("/sim/ai/groundservices",1).getChild("vehicle", sim_ai_index, 1);
	var model = vehicle_node.getNode("model", 1).getValue();		
	var type  = vehicle_node.getNode("type", 1).getValue();
	var maximumspeed = vehicle_node.getNode("maximumspeed",1).getValue() or 5;
	# zoffset 0 will be used when no tag exists.
	var zoffset = vehicle_node.getNode("zoffset",1).getValue() or 0;
    var unscheduledmoving = vehicle_node.getNode("unscheduledmoving",1).getValue();
    if (unscheduledmoving == nil) {
        unscheduledmoving = 1;
    }
	
	var gmc = nil;
    if (graphposition == nil){
	    logging.debug("no position. using home ");
	    var home = groundnet.getVehicleHome();
        if (home != nil) {
            graphposition = groundnet.getParkingPosition(home);            
        }
	    if (type == "aircraft") {
	        # position aircraft to the southwest most park position (just arbitrary).
	        var southwest = cloneCoord(center).apply_course_distance(225, 25000);
	        var parking = groundnet.getParkPosNearCoordinates(southwest);
	        if (parking != nil) {
	            logging.debug("new aircraft at parking "~parking.toString());
	            var newgraphposition = groundnet.getParkingPosition(parking);
	            if (newgraphposition != nil){
	                graphposition=newgraphposition;
	            }
	        }
	    }
	    if (graphposition == nil) {
            logging.warn("still no position. No vehicle created.");
            return;
        }
	}
    gmc = GraphMovingComponent.new(nil,nil,graphposition,unscheduledmoving);	
	var vehicle = GroundVehicle.new( model, gmc, maximumspeed, type,delay, zoffset );
	return vehicle;
}


var requestMove = func(vehicletype, parkposname) {
    foreach (var v; values(GroundVehicle.active)){
        if (v.type == vehicletype) {
            logging.debug("requestMove for "~v.aiid);
            #24.4.18: Broken? TODO
            var destinationnode =
            var path = groundnet.groundnetgraph.findPath(v.gmc.currentposition, destinationnode, nil);
            #if (visualizer != nil) {
            #    visualizer.displayPath(path);
            #}
            v.gmc.setPath(path);
        }
    }
}

#
# Request service at some specific parkpos, for an arrive aircraft or for current aircraft
#
var requestService = func(aircraftlabel = nil, parkpos = nil) {
    if (parkpos == nil and aircraftlabel == nil) {
        logging.debug("requestService for me");            
        var myaircraft =  buildArrivedAircraft(nil, getAircraftPosition(), "737", "callsign", getAircraftHeading(),-1); 
        spawnService(myaircraft);
    } else {
        if (aircraftlabel == nil) {
            var parking = groundnet.getParkPos(parkpos);
            if (parking != nil) {
                 logging.debug("requestService for parkpos "~parkpos);
                 #assume a 737. parkpos might be empty
                 var virtualaircraft = buildArrivedAircraft(nil, parking.node.coord, "737", "--", parking.heading,0);
                 spawnService(virtualaircraft);
             } else {
                logging.warn("inknown parkpos "~parkpos);
             }
        } else {
            logging.debug("requestService for arrived aircraft "~aircraftlabel);
            var keys = keys(arrivedaircraft);
            if (size(keys)>0){
                spawnService(arrivedaircraft[keys[0]]);
            }
        }
    }
}

#
#
#
var update = func() {
    		
    if (statusNode.getValue() == "standby") {
        if (checkWakeup()){
            wakeup();   
            settimer(func update(), 0);
        }else{
            # try again 15 seconds later
            settimer(func update(), 15);
        }
        return;
    }
    var deltatime = getprop("sim/time/delta-sec");
    var currenttime = math.round(systime());
    
    # current state is active
        
    # is there a better solution for detecting left airport?
    if (lastcheckforstandby < currenttime - 15) {
        lastcheckforstandby = currenttime;
        var icao = findAirport();
        # airport might suddenly change due to rapid move of aircraft. Intermediate change to standby is required.
        if (icao == nil or icao != getCurrentAirportIcao()) {
            # airport left
            logging.info("going to standby because airport was left");
            shutdown();
            settimer(func update(), 5);
            return;
        }
        # no relation to left airport; just to have the call at some interval
        if (groundnet.altneedsupdate) {
            groundnet.updateAltitudes();      
        }
        
    }
    if (last120 < currenttime - 120) {
        last120 = currenttime;
        var stat = "";
        if (groundnet != nil and groundnet.groundnetgraph != nil) {
            stat ~= groundnet.groundnetgraph.getStatistic();
        }
        logging.info("statistics: "~stat);
    }
    
    # check regularly for aircrafts needing service
    if (lastcheckforaircraft < currenttime - checkforaircraftinterval) {
        lastcheckforaircraft = currenttime;
        var radius = collectradius;
        if (currenttime > activetimestamp + 60 and size(arrivedaircraft) == 0) {
            radius += collectradius;
        }
        collectAllArrivedAircraftWithinRadius(radius);               
    }

    # 2 second interval for serviuce points and schedules
    if (lastscheduling < currenttime - schedulinginterval) {
        lastscheduling = currenttime;
        
        if (autoserviceNode.getValue()) { 
            var akeys = keys(arrivedaircraft);                    
            foreach (var key ; akeys) {
                var aircraft = arrivedaircraft[key];
                if (!aircraft.receivingservice and size(servicepointsN.getChildren("servicepoint")) < maxservicepoints) {
                    spawnService(aircraft);
                }
            }                                  
        }
        
        var skeys = keys(schedules);              
        for (var i = size(skeys) - 1; i >= 0; i=i-1) {        
            var s = schedules[skeys[i]];
            # progress actions of schedule
            for (var j = size(s.actions) - 1; j >= 0; j=j-1) {
                var a = s.actions[j];
                if (a.isActive() and a.checkCompletion()) {
                    #actionsactive.remove(j);
                    #s.actions[j] = nil;
                }
            }
            var action = s.next();
            if (action != nil) {
                action.trigger();            
            }
            if (s.checkCompletion()) {
                logging.info(s.toString() ~ " completed.");
                s.delete();            
            }
        }
        
        # check for completed SPs
        skeys = keys(servicepoints);
        for (var i = size(skeys) - 1; i >= 0; i=i-1) {
            var sp = servicepoints[skeys[i]];
            if (sp.cateringschedule.isCompleted() and sp.fuelschedule.isCompleted()) {
                sp.delete();                
            }
        }
                
        # individual service scenarios
        if (size(arrivedaircraft) > 2 and scenario == 0){
            requestService("C_4");
            scenario = 1;
        }
    }
    
    #update vehicles in every frame.          
    foreach (var v; values(GroundVehicle.active)) {
        var gmc = v.gmc;
        var vhc = v.vhc;
        
		v.update(deltatime);
        
        # check for completed movment
        #var p = nil;
        #if ((p = vhc.isMoving()) != nil and gmc.pathCompleted()) {
        #    groundnet.groundnetgraph.removeLayer(p.layer);
        #    vhc.setStateIdle();
        #}        

        if (automoveNode.getValue()) {                    
            #spawn moving for idle vehicles to random destination
            if (gmc.unscheduledmoving and expiredIdle(gmc,vhc,maxidletime) and !vhc.isScheduled()) {             
                vhc.lastdestination = getNextDestination(vhc.lastdestination);
                logging.debug("Spawning move to " ~ vhc.lastdestination.getName());                
                spawnMoving(v, vhc.lastdestination);
            }
        }
    }
    
    if (math.mod(currenttime,60)==0){
        
            
    }
    settimer(func update(), 0);
}

var expiredIdle = func(gmc,vhc,maxidletime) {
	#logging.debug("currentstate is "~me.state);
	if (!vhc.isIdle()) {
        return 0;
    }
    if (gmc.isMoving() != nil) {
        return 0;
    }
    if (vhc.statechangetimestamp + maxidletime > systime()) {
        return 0;
    }
    if (gmc.statechangetimestamp + maxidletime > systime()) {
        return 0;
    }
    return 1;
}
    
var spawnMoving = func(vehicle, destinationnode) {
    var gmc = vehicle.gmc;
    
    var path = groundnet.createPathFromGraphPosition(gmc.currentposition, destinationnode, nil, true, -300000, false, vehicle.vhc.config);
    if (path!=nil) {  
        if (visualizer != nil) {
            visualizer.addLayer(groundnet.groundnetgraph,path.layer);
        }
        vehicle.gmc.setPath(path);        
    }
};

#spawn service point for aircraft    
var spawnService = func(aircraft) {
    var positionXY = projection.project(aircraft.coord);
    var aircraftconfig = getAircraftConfiguration(aircraft.type);
    var sp = ServicePoint.new(groundnet, aircraft, buildFromVector2(positionXY), aircraft.heading, aircraftconfig);                               
    servicepoints[sp.node.getValue("id")] = sp;
    var schedule = Schedule.new(sp, groundnet);
    schedule.addAction(VehicleOrderAction.new(schedule, VEHICLE_CATERING, sp.doorEdge.from));
    schedule.addAction(VehicleServiceAction.new(schedule,cateringdurationNode.getValue()));
    schedule.addAction(VehicleReturnAction.new(schedule, 1,sp,1));
    addSchedule(schedule);
    sp.cateringschedule = schedule;
    schedule = Schedule.new(sp, groundnet);
    schedule.addAction(VehicleOrderAction.new(schedule, VEHICLE_FUELTRUCK, sp.wingedge.to));
    schedule.addAction(VehicleServiceAction.new(schedule,fuelingdurationNode.getValue()));
    schedule.addAction(VehicleReturnAction.new(schedule, 0,sp,0));
    addSchedule(schedule);
    sp.fuelschedule = schedule;
}


#might return lastdestination if no other is found. try 10 times to get other than last destination.
var getNextDestination = func(lastdestination) {
    var destination = nil;
    for (var cnt=0;cnt<10;cnt+=1) {
        if (destinationlist == nil or size(destinationlist) == 0) {
            # use random destination. If we hava enough parking nodes (lets say 10) only use these as destination to avoid
            # vehicles to end up on a runway.
            if (size(groundnet.parkingnodes) > 10) {
                destination = groundnet.parkingnodes[math.mod(randnextInt(), size(groundnet.parkingnodes))];
            } else {
                destination = groundnet.groundnetgraph.getNode(math.mod(randnextInt(), groundnet.groundnetgraph.getNodeCount()));
            }
        } else {
            var index = math.mod(randnextInt(), size(destinationlist) + 1);
            logging.debug("using random predefined destination index " ~ index);
            if (index == size(destinationlist)) {
                destination = groundnet.getVehicleHome().node;
            } else {
                var parkposname = destinationlist[index];
                logging.debug("trying parkpos " ~ parkposname ~ " as next destination");
                var parkpos = groundnet.getParkPos(parkposname);
                if (parkpos == nil){
                    logging.warn("parkpos " ~ parkposname ~ " not found");
                    destination = lastdestination;
                } else {
                    destination = parkpos.node;
                }
            }
        }
        #TODO temprary node
        if (destination != lastdestination) {        
            return destination;
        }
    }       
    return lastdestination;
};
        
var shutdown = func() {
    #remove existing stuff. TODO get rid off timer
    removeGroundnetModel();
    
    if (refmarkermodel != nil) {
        refmarkermodel.remove();
        refmarkermodel = nil;
    }
    foreach (var v; values(GroundVehicle.active))
		v.del();
	
	var skeys = keys(schedules);                              	
    for (var i = size(skeys) - 1; i >= 0; i=i-1) {        
        var s = schedules[skeys[i]];
        s.delete();                    
    }
    skeys = keys(servicepoints);
    for (var i = size(skeys) - 1; i >= 0; i=i-1) {
        var sp = servicepoints[skeys[i]];
        sp.delete();                        
    }
    arrivedaircraft = {};
    logging.info("shut down");
    statusNode.setValue("standby");
}

var setRefMarker = func() {
    var path = "Aircraft/ufo/Models/marker.ac";
    var course = 0;
    # Ende des Taxiway an der Wende zu 14R (index 85)
    logging.debug("adding marker at 85: 50.853868,7.160852");
    var coord = geo.Coord.new().set_latlon(50.853868,7.160852);
    refmarkermodel = geo.put_model(path, coord, course);
};

var initNode = func(subpath, value, type) {
    var PROPGROUNDSERVICES = "/groundservices/";
    var node = props.globals.initNode(PROPGROUNDSERVICES~subpath, value, type);
    node.setValue(value);
    return node;
};

# TODO see core lib setlistener doc
var initProperties = func() {
    simaigroundservicesN = props.globals.getNode("/sim/ai/groundservices",1);

    var PROPGROUNDSERVICES = "/groundservices";
    var PROPVISUALIZEGROUNDNET = "visualizegroundnet";
    var PROPVISUALIZEPARKING = "visualizeparking";
    #visualizegroundnetNode = props.globals.getNode(PROPGROUNDSERVICES~"/"~PROPVISUALIZEGROUNDNET,1);
    statusNode = initNode("status", "standby", "STRING");
    airportNode = initNode("airport", "", "STRING");
    visualizegroundnetNode = initNode("visualizegroundnet", 0, "INT");
    setlistener(visualizegroundnetNode,visualizeGroundnet);
    props.globals.getNode(PROPGROUNDSERVICES~"/"~PROPVISUALIZEPARKING,1);
    automoveNode = initNode("automove", getNodeValue(simaigroundservicesN,"config/automove",1), "INT");
    autoserviceNode = initNode("autoservice", getNodeValue(simaigroundservicesN,"config/autoservice",1), "INT");
    scalefactorNode = initNode("scalefactor", getNodeValue(simaigroundservicesN,"config/scalefactor",1), "INT");
    approachoffsetNode = initNode("approachoffset", getNodeValue(simaigroundservicesN,"config/approachoffset",1), "INT");
    maxservicepointsNode = initNode("maxservicepoints", getNodeValue(simaigroundservicesN,"config/maxservicepoints",1), "INT");
    cateringdurationNode = initNode("cateringduration", getNodeValue(simaigroundservicesN,"config/cateringduration",1), "INT");
    fuelingdurationNode = initNode("fuelingduration", getNodeValue(simaigroundservicesN,"config/fuelingduration",1), "INT");
                
    schedulesN = props.globals.getNode(PROPGROUNDSERVICES~"/schedules",1);
    servicepointsN = props.globals.getNode(PROPGROUNDSERVICES~"/servicepoints",1);
    maprangeNode = initNode("maprange", 0.7, "DOUBLE");
        
}

#
# wakeup from state standby. airport and groundnet info is already set.
var wakeup = func() {
    #var delay = 0;
    logging.debug("wakeup: loading initial settings. scalefactor="~scalefactor~",maxservicepoints="~maxservicepoints);
    
    #var totalcnt = 0;
    #foreach (var vehicle_node;simaigroundservicesN.getChildren("vehicle")){
    #    var sim_ai_index = vehicle_node.getIndex();
    #    var cnt=vehicle_node.getValue("initialcount") or 0;
    #    totalcnt += cnt;
    #}

    var automoveinterval = 20;
    var offset = maxidletime;          
    foreach (var vehicle_node;simaigroundservicesN.getChildren("vehicle")){
        var sim_ai_index = vehicle_node.getIndex();
        var cnt=vehicle_node.getValue("initialcount") or 0;
        cnt *= scalefactor;
        #if (){
            #delay += 0;
        #}
        logging.debug("init vehicle " ~ sim_ai_index ~ " with " ~ cnt ~ " instances");
        for (var i=0;i<cnt;i+=1){
            # initial position will be set to defined home pos. delay is no longer used here. Instead the last statechangetimestamp is set to the past         
            var vehicle = createVehicle(sim_ai_index,nil,0);
            # Only set delay value if autostart is active? No, why. Even for Servicing vehicles should start one after the other
            #if (automoveNode.getValue()){
                #delay += 8;
            #}
            vehicle.initStatechangetimestamp(offset);
            offset -= automoveinterval;
        }
    }
    	            
    #give AI aircrafts 15 seconds for settling
    lastcheckforaircraft = systime();
    checkforaircraftinterval = 15;
    activetimestamp = systime();
    logging.info("Going active");
    statusNode.setValue("active");
    #openMap();        
};


#
# change from active mode to state standby
var standby = func() {
    if (statusNode.getValue() != "active") {
        logging.warn("Ignoring standby due to state " ~ statusNode.getValue());
        return;
    }
}

# check whether change to state active is possible. Requires airport nearby and
# elevation data available
# Return 1 if wakeup is possible, 0 otherwise
var checkWakeup = func() {
    if (statusNode.getValue() != "standby") {
        logging.warn("Ignoring wakeup due to state " ~ statusNode.getValue());
        return 0;
    }
    if (getAirportInfo()){
        var icao = airportNode.getValue();
        projection = Projection.new(center);   
        var altinfo = getElevationForLocation(center);
        # airport can only be used if scenery is loaded (for elevation data)
        if (!altinfo.needsupdate) {
            var subpath = chr(icao[0]) ~ "/" ~ chr(icao[1]) ~ "/" ~ chr(icao[2]) ~ "/" ~ icao;
            var path = findGroundnetXml("Airports/" ~ subpath ~ ".groundnet.xml");        
            if (path == nil) {
                logging.error("no groundnet path for airport " ~ icao ~ ". Added to ignorelist");
                failedairports[icao] = icao;
                return;    
            }
            var data = loadGroundnet(path); 
            if (data == nil) {
                logging.warn("no groundnet for airport " ~ icao ~ ". Added to ignorelist");
                failedairports[icao] = icao;
                return 0;    
            }
            var homenode = props.globals.getNode("/sim/ai/groundservices/airports/" ~ icao ~ "/home",0);
            homename = nil;
            if (homenode != nil){
                homename = homenode.getValue(); 
                logging.info("using home " ~ homename);
            }
            
            groundnet = Groundnet.new(projection, data.getChild("groundnet"), homename);
            logging.info("groundnet loaded from "~path);
            logging.info("groundnet graph has "~groundnet.groundnetgraph.getEdgeCount()~" edges");
            if (groundnet.groundnetgraph.getEdgeCount() == 0) {
                logging.warn("no edges in groundnet for airport " ~ icao ~ ". Added to ignorelist");
                failedairports[icao] = icao;
                return 0;    
            }
            groundnet.multilaneenabled = true;
                        
            # read destination list
            destinationlist=[];
            var destinationlistnode = props.globals.getNode("/sim/ai/groundservices/airports/" ~ icao ,0);
            if (destinationlistnode != nil) {
                for (var i = 0; 1; i += 1) {
                    var destinationnode = destinationlistnode.getChild("destination", i, 0);
                    if (destinationnode == nil)
                        break;
                    append(destinationlist,destinationnode.getValue());
                }
            }
            scalefactor = groundnet.groundnetgraph.getNodeCount() / scalefactorNode.getValue();
            maxservicepoints = maxservicepointsNode.getValue() * scalefactor;         
            return 1;
        }
        logging.warn("ignoring airport. No elevation info");
    }
    return 0;
}

# called after initial load and reload.
var reinit = func {
    logging.info("reinit");
    if (statusNode == nil){
        # first time reinit
        initProperties();
    }
	shutdown();
	var path = getprop("/sim/fg-home") ~ '/runtest';
    if (fileExists(path)) {
        maintest();
        var debugcmdNode = initNode("debugcmd","--", "STRING");	
        setlistener(debugcmdNode, func {
            var debugcmd = debugcmdNode.getValue();
            execDebugcmd(debugcmd);            
        });    
	} else {
	    # switch off debug log level in production
	    logging.loglevel = LOGLEVEL_INFO;
	}
	fgroot = getprop("/sim/fg-root");
	#init is done in wakeup through update()
                
    update();
}

#20.11.17:not used in addon
#setlistener("/nasal/groundservices/loaded", func {
#    logging.debug("main: module groundservices loaded");
    #not used currently initremoteeventhandler();
#    reinit();
#});

#_setlistener("/sim/signals/nasal-dir-initialized", func {
	#var aar_capable = true;
	#gui.menuEnable("groundservice", aar_capable);
	#if (!aar_capable)
	#	request = func { atc_msg("no tanker in range") }; # braces mandatory

	#setlistener("/sim/signals/reinit", reinit, 1);
#});

logging.debug("completed main.nas");

