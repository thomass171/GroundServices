#
# 
#

logging.debug("executing main.nas");

#--------------------------------------------------------------------------------------------------

var showTestMessage = func(msg) {
    logging.debug(msg);
	gui.popupTip("Graph Test Message: " ~ msg);
}

var modulename = "main";


var oclock = func(bearing) int(0.5 + geo.normdeg(bearing) / 30) or 12;
var airportelevation = 0;


var tanker_msg = func setprop("sim/messages/ai-plane", call(sprintf, arg));
var pilot_msg = func setprop("/sim/messages/pilot", call(sprintf, arg));
var atc_msg = func setprop("sim/messages/atc", call(sprintf, arg));

var basepos =  geo.Coord.new().set_latlon(50.883056,7.116523,400);
var groundnet = nil;
var center = nil;

var refmarkermodel = nil;
var projection = nil;
var lastcheckforstandby = 0;

# Nodes
var visualizegroundnetNode = nil;
var statusNode = nil;
# current/next/near airport
var airportNode = nil;

var maxidletime = 0;
var failedairports = {};
var minairportrange = 3;
var homename = nil;
var destinationlist = nil;


var report = func {
    atc_msg("Ground Service Status: "~statusNode.getValue());
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
                logger.warn("Ignoring previously failed airport " ~ apt.id);
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
    
#
# Create an additional ground vehicle based on a given /sim/ai/groundservices/vehicle property node.
# has index parameter to be callable by dialogs.
#
var createVehicle = func(sim_ai_index, graphposition=nil) {
    logging.debug(modulename~".createVehicle");
    course=0;
    vehicle_node = props.globals.getNode("/sim/ai/groundservices",1).getChild("vehicle", sim_ai_index, 1);
	var model = vehicle_node.getNode("model", 1).getValue();		
	var type  = vehicle_node.getNode("type", 1).getValue();
	var movementspeed = vehicle_node.getNode("movementspeed",1).getValue() or 5;
		
	var gmc = nil;
    if (graphposition == nil){
	    logging.debug("no position. using home ");
	    var home = groundnet.getVehicleHome();
	    graphposition = groundnet.getParkingPosition(home);
	    if (graphposition == nil) {
	        logging.warn("still no position. No vehicle created.");
	        return;
	    }
	}
    gmc = GraphMovingComponent.new(nil,nil,graphposition);	
	GroundVehicle.new( model, gmc, movementspeed, type);
}


var requestMove = func(vehicletype, parkposname) {
    foreach (var v; values(GroundVehicle.active)){
        if (v.type == vehicletype) {
            logging.debug("requestMove for "~v.aiid);
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
#
#
var update = func() {
    		
    if (statusNode.getValue() == "standby") {
        if (checkWakeup()){
            wakeup();   
            settimer(func update(), 0);
        }else{
            settimer(func update(), 5);
        }
        return;
    }
    # is there a better solution for detecting left airport
    if (statusNode.getValue() == "active" and lastcheckforstandby < systime() - 15) {
        lastcheckforstandby = systime();
        var icao = findAirport();
        if (icao == nil){
            # airport left
            logging.info("going to standby");
            shutdown();
            settimer(func update(), 5);
            return;
        }       
    }
    var deltatime = getprop("sim/time/delta-sec");
    foreach (var v; values(GroundVehicle.active)) {
        var gmc = v.gmc;
        var vhc = v.vhc;
        
		v.update(deltatime);
        
        # check for completed movment
        var p = nil;
        if ((p = vhc.isMoving()) != nil and gmc.pathCompleted()) {
            if (visualizer != nil) {
                visualizer.removeLayer(p.layer);
            }
            groundnet.groundnetgraph.removeLayer(p.layer);
            vhc.setStateIdle();
        }        
                    
        #spawn moving for idle vehicles to random destination
        if (vhc.expiredIdle(maxidletime)) {             
            vhc.lastdestination = getNextDestination(vhc.lastdestination);
            logging.debug("Spawning move to " ~ vhc.lastdestination.getName());                
            spawnMoving(v, vhc.lastdestination);
        }
    }
    settimer(func update(), 0);
}

var spawnMoving = func(vehicle, destinationnode) {
    var gmc = vehicle.gmc;
    var path = groundnet.createPathFromGraphPosition(groundnet.groundnetgraph,gmc.currentposition, destinationnode);
    if (path!=nil) {  
        if (visualizer != nil) {
            visualizer.addLayer(groundnet.groundnetgraph,path.layer);
        }
        vehicle.gmc.setPath(path);
        vehicle.vhc.setStateMoving(path);
    }
};

#might return lastdestination if no other is found. try 10 times to get other than last destination.
var getNextDestination = func(lastdestination) {
    var destination = nil;
    for (var cnt=0;cnt<10;cnt+=1) {
        if (destinationlist == nil or size(destinationlist) == 0) {
            # use random destination
            destination = groundnet.groundnetgraph.getNode(math.mod(randnextInt(), groundnet.groundnetgraph.getNodeCount()));
        } else {
            var index = math.mod(randnextInt(), size(destinationlist) + 1);
            logging.debug("using random destination index " ~ index);
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
    var PROPGROUNDSERVICES = "/groundservices";
    var PROPVISUALIZEGROUNDNET = "visualizegroundnet";
    var PROPVISUALIZEPARKING = "visualizeparking";
    visualizegroundnetNode = props.globals.getNode(PROPGROUNDSERVICES~"/"~PROPVISUALIZEGROUNDNET,1);
    statusNode = initNode("status", "standby", "STRING");
    airportNode = initNode("airport", "", "STRING");
    setlistener(visualizegroundnetNode,visualizeGroundnet);
    props.globals.getNode(PROPGROUNDSERVICES~"/"~PROPVISUALIZEPARKING,1);
    props.globals.getNode("/inputgs/heading",1).setValue(7.139103);
    props.globals.getNode("/inputgs/pitch",1).setValue(50.86538-90);
    props.globals.getNode("/inputgs/roll",1).setValue(90);
}

#
# wakeup from state standby. airport and groundnet info is already set.
var wakeup = func() {
    logging.debug("wakeup: loading initial settings");
    foreach (var vehicle_node;props.globals.getNode("/sim/ai/groundservices",1).getChildren("vehicle")){
        var sim_ai_index = vehicle_node.getIndex();
        var cnt=vehicle_node.getValue("initialcount") or 0;
        logging.debug("init vehicle " ~ sim_ai_index ~ " with " ~ cnt ~ " instances");
        for (var i=0;i<cnt;i+=1){
            # initial position will be set to defined home pos                 
            createVehicle(sim_ai_index);
        }
    }
    	    
    #var parkpos_c_7 = groundnet.getParkPos("C_7");
    #logging.debug("setting marker at C_7 at " ~ parkpos_c_7.node.getLocation().toString());        
    #var graphposition = GraphPosition.new(parkpos_c_7.node.getEdges()[0]);
    #setMarkerAtNode(parkpos_c_7.node,2);            
    #createVehicle(2, graphposition);
    #var parkpos_c_4 = groundnet.getParkPos("C_4");
    #setMarkerAtNode(parkpos_c_4.node,1);
    #debug.dump(parkpos_c_4.node);
    #graphposition = GraphPosition.new(parkpos_c_4.node.getEdges()[0]);    
    #createVehicle(1, graphposition);
        
    logging.debug("Going active");
    statusNode.setValue("active");
}

#
# change from active mode to state standby
var standby = func() {
    if (statusNode.getValue() != "active") {
        logging.warn("Ignoring standby due to state " ~ statusNode.getValue());
        return;
    }
}

var checkWakeup = func() {
    if (statusNode.getValue() != "standby") {
        logging.warn("Ignoring wakeup due to state " ~ statusNode.getValue());
        return 0;
    }
    if (getAirportInfo()){
        var icao = airportNode.getValue();
        projection = Projection.new(center);   
          
        var subpath = chr(icao[0]) ~ "/" ~ chr(icao[1]) ~ "/" ~ chr(icao[2]) ~ "/" ~ icao;
        var path = getprop("/sim/fg-home") ~ "/TerraSync/Airports/" ~ subpath ~ ".groundnet.xml";        
        var data = loadGroundnet(path); 
        if (data == nil) {
            logging.error("no groundnet for airport " ~ icao ~ ". Added to ignorelist");
            failedairports[icao] = icao;
            return;    
        }
        var homenode = props.globals.getNode("/sim/ai/groundservices/airports/" ~ icao ~ "/home",0);
        homename = nil;
        if (homenode != nil){
            homename = homenode.getValue(); 
            logging.info("using home " ~ homename);
        }
        
        groundnet = Groundnet.new(projection, data.getChild("groundnet"), homename);
        logging.info("groundnet loaded from "~path);
        
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
        return 1;
    }
    return 0;
}

# called after initial load and reload.
var reinit = func {
    logging.debug("reinit");
    if (statusNode == nil){
        # first time reinit
        initProperties();
    }
	shutdown();
	var path = getprop("/sim/fg-home") ~ '/runtest';
    if (io.stat(path) != nil) {
	    maintest();
	}
	#init is done in wakeup through update()
                
    update();
}

setlistener("/nasal/groundservices/loaded", func {
    logging.debug("main: module groundservices loaded");
    #not used currently initremoteeventhandler();
    reinit();
});

#_setlistener("/sim/signals/nasal-dir-initialized", func {
	#var aar_capable = true;
	#gui.menuEnable("groundservice", aar_capable);
	#if (!aar_capable)
	#	request = func { atc_msg("no tanker in range") }; # braces mandatory

	#setlistener("/sim/signals/reinit", reinit, 1);
#});

logging.debug("completed main.nas");

