#
# The global id is assigned here
#

logging.debug("executing GroundVehicle.nas");

var baseid = 5567;
var lastlogsecond = 0;



var GroundVehicle = {
	new: func(model, gmc, movementspeed, type) {
	    logging.debug("new GroundVehicle. model="~model);
		#props.globals.getNode("gear/gear[0]/wow", 1).setValue(1);
		#props.globals.getNode("sim/model/pushback/enabled", 1).setValue(1);

		var m = { parents: [GroundVehicle] };
		m.interval = 10;
		m.coord = geo.Coord.new();
		m.gmc = gmc;
        
		var n = props.globals.getNode("models", 1);
		for (var i = 0; 1; i += 1)
			if (n.getChild("model", i, 0) == nil)
				break;
		m.model = n.getChild("model", i, 1);

		var n = props.globals.getNode("ai/models", 1);
		for (var i = 0; 1; i += 1)
			if (n.getChild("gsvehicle", i, 0) == nil)
				break;
		m.ai = n.getChild("gsvehicle", i, 1);

        m.aiid = baseid;
        baseid = baseid +1;
        m.vhc = VehicleComponent.new(type,m.aiid);
                
        m.ai.getNode("id", 1).setIntValue(m.aiid);
		m.ai.getNode("vehicle", 1).setBoolValue(1);
		m.ai.getNode("valid", 1).setBoolValue(1);
		 
        
		m.latN = m.ai.getNode("position/latitude-deg", 1);
		m.lonN = m.ai.getNode("position/longitude-deg", 1);
		m.altN = m.ai.getNode("position/altitude-ft", 1);
		m.hdgN = m.ai.getNode("orientation/true-heading-deg", 1);
		m.movementspeedN = m.ai.getNode("movementspeed", 1);		
        m.movementspeedN.setValue(movementspeed);
        
		#m.update();
		
		# link nodes from current "/ai/models/gsvehicle" to corresponding "/models/model[]" entry                
		
		m.model.getNode("path", 1).setValue(model);
		m.model.getNode("latitude-deg-prop", 1).setValue(m.latN.getPath());
		m.model.getNode("longitude-deg-prop", 1).setValue(m.lonN.getPath());
		m.model.getNode("elevation-ft-prop", 1).setValue(m.altN.getPath());
		m.model.getNode("heading-deg-prop", 1).setValue(m.hdgN.getPath());
		m.model.getNode("load", 1).remove();
		
		# set initial position 
		if (gmc != nil) {
		    m.adjustVisual(gmc);
		} else {
		    var coord = geo.Coord.new(basepos);
		    m.latN.setDoubleValue(coord.lat());
            m.lonN.setDoubleValue(coord.lon());                		               
        }        
        var alt = getCurrentAltitude();
       	m.altN.setDoubleValue(alt * M2FT);
       	                
        return GroundVehicle.active[m.aiid] = m;
	},
	del: func {
		logging.debug("del");
		me.model.remove();
		me.ai.remove();
		delete(GroundVehicle.active, me.aiid);
		tanker_msg("vehicle " ~ me.aiid ~ " removed");
        		
	},
	update: func(deltatime) {
	    var currenttime = systime();
	    # rounding problem?
	    if (lastlogsecond != currenttime){
	        lastlogsecond = currenttime;
	        #logging.debug("update");
	    }
	    
	    #if (me.gmc == nil) {
	        #auto rotate
		    #var radius = me.radiusNode.get
           # me.position = me.position + (me.speed * deltatime);
            #var x = math.cos(me.position) * me.radius;
            #var y = math.sin(me.position) * me.radius;
            #me.setPositionFromXY({x:x,y:y});
                 
		#}
		    me.moveForward(deltatime);
		
        
        	
        #me.coord = geo.Coord.new(basepos);
        #		me.ac = geo.aircraft_position();
        #		me.distance = me.ac.distance_to(me.coord);
        #		me.bearing = me.ac.course_to(me.coord);
        #		settimer(func me.update(), 0);
	},
	
	setPositionFromXY: func(posXY){
	    var coord = projection.unproject(posXY);
	    #logging.debug("setPositionFromXY: x=" ~ posXY.x ~ ",y=" ~ posXY.y ~ ",lat=" ~ coord.lat() ~ ",lon=" ~ coord.lon());
	    me.latN.setDoubleValue(coord.lat());
        me.lonN.setDoubleValue(coord.lon());
        return coord;
	},
	
	moveForward: func(deltatime) {
        var gmc = me.gmc;
       
        if (gmc.automove) {
            var speed = me.movementspeedN.getValue();
            gmc.moveForward(deltatime * speed);
            me.adjustVisual(gmc);  
        }                          
    },
    
    adjustVisual: func(gmc) {         
        var cp = gmc.currentposition;            
        var positionXYZ = cp.get3DPosition();
        #logging.debug("3Dposition="~positionXYZ.toString());
        var coord = me.setPositionFromXY(positionXYZ);
        var heading = get3DRotation(coord,cp.edgeposition,cp.reverseorientation,cp.currentedge.getEffectiveDirection( cp.getAbsolutePosition()));
        me.hdgN.setValue(heading);            
    },
	
	report: func {
		#me.out_of_range_time = me.now;
		#var dist = int(me.distance * M2NM);
		#var hdg = getprop("orientation/heading-deg");
		#var diff = (me.coord.alt() - me.ac.alt()) * M2FT;
		#var qual = diff > 3000 ? " well" : abs(diff) > 1000 ? " slightly" : "";
		#var rel = diff > 1000 ? " above" : diff < -1000 ? " below" : "";
		var statemsg = me.vhc.state;
		if (me.vhc.state == MOVING) {
		    statemsg = "moving to node " ~ ((me.vhc.lastdestination!=nil)?me.vhc.lastdestination.getName():"");
		}
		atc_msg("GroundVehicle %s %s %s",me.vhc.type,me.aiid,statemsg);
	},
	
	
	active: {},
};

var GraphMovingComponent = {
    
    new: func(dummy1, dummy2, currentposition) {	    
	    var obj = { parents: [GraphMovingComponent] };
		obj.currentposition = currentposition;
		obj.automove = 0;
		obj.path = nil;
		obj.selector = nil;
		return obj;
	},
	
	setPath: func (path) {
        logging.debug("setPath");
        me.path = path;
        me.automove = 1;
        me.selector = GraphPathSelector.new(path);
    },
    	        	
    moveForward: func( amount) {
        #logging.debug("moveForward "~amount ~ ",currentposition="~me.currentposition.toString());    
        if (amount > 0) {
            me.currentposition.edgeposition += amount;
            while (me.currentposition.edgeposition > me.currentposition.currentedge.len) {
                var outbound = (me.currentposition.reverseorientation) ? me.currentposition.currentedge.from : me.currentposition.currentedge.to;
                var newedge = me.selector.findNextEdgeAtNode(me.currentposition.currentedge, outbound);
                if (newedge == nil) {
                    me.currentposition.edgeposition = me.currentposition.currentedge.len;
                    if (me.path != nil) {
                        me.movepathCompleted();
                    }
                } else {
                    if (outbound == newedge.from) {
                        me.currentposition.reverseorientation = 0;
                    } else {
                        me.currentposition.reverseorientation = 1;
                    }
                    me.currentposition.edgeposition -= me.currentposition.currentedge.getLength();
                    me.currentposition.currentedge = newedge;
                }
            }
        }

        if (amount < 0) {
            me.currentposition.edgeposition += amount;
            while (me.currentposition.edgeposition < 0) {
                var inbound = (me.currentposition.reverseorientation) ? me.currentposition.currentedge.to : me.currentposition.currentedge.from;
                var newedge = me.selector.findNextEdgeAtNode(me.currentposition.currentedge, inbound);
                if (newedge == nil) {
                    me.currentposition.edgeposition = 0;
                    if (me.path != nil) {
                        me.movepathCompleted();
                    }
                } else {
                    if (inbound == newedge.to) {
                        me.currentposition.reverseorientation = 0;
                    } else {
                        me.currentposition.reverseorientation = 1;
                    }
                    me.currentposition.edgeposition = newedge.len + me.currentposition.edgeposition;
                    me.currentposition.currentedge = newedge;
                }
            }
        }
    },

    movepathCompleted: func() {
        logging.info("move path completed at " ~ me.currentposition.toString());
        # find corresponding position in layer 0 if a path was used.
        var nextnode = me.currentposition.getNodeInDirectionOfOrientation();
        var dir = me.currentposition.currentedge.getEffectiveInboundDirection(nextnode);
        var newpos = nil;
        foreach (var e ; nextnode.edges) {
            #be quite tolerant
            if (e.getLayer() == 0 and getAngleBetween(e.getEffectiveInboundDirection(nextnode), dir) < 0.01) {
                newpos = buildPositionAtNode(e, nextnode, 0);
                logging.debug("switching to new current position in layer 0:" ~ newpos.toString());
                break;
            }
        }
        if (newpos == nil) {
            logging.error("No corresponding position in layer 0");
        } else {
            me.currentposition = newpos;
        }
        me.path=nil;
        me.automove=0;        
    },    	    
        	
    pathCompleted: func() {
        return me.path==nil;
    },        
};

# Return heading in degree
var get3DRotation = func(coord, edgeposition, reverseorientation, effectivedirection) {
    if (reverseorientation) {
        effectivedirection = effectivedirection.negate();
    }
    var heading = getTrueHeadingFromDirection(coord,effectivedirection);
    #logging.debug("get3DRotation: edgeposition=" ~ edgeposition ~ ",reverseorientation="~reverseorientation~",effectivedirection="~effectivedirection.toString()~",heading="~heading);
    return heading;            
};
        
var GraphPathSelector = {
    
    new: func(path) {	    
	    var obj = { parents: [GraphPathSelector] };
		obj.path = path;
		return obj;
    },
    
    findNextEdgeAtNode: func( incomingedge,  node) {
        var index = -1;

        for (var i = 0; i < me.path.getSegmentCount(); i+=1) {
            var e = me.path.getSegment(i).edge;
            if (e == incomingedge){
                index=i;
            }
        }

        if (index < me.path.getSegmentCount() - 1) {
            var edge = me.path.getSegment(index + 1).edge;        
            #logging.debug("findNextEdgeAtNode:" ~ ((edge!=nil)?edge.toString():"nil"));        
            return edge;
        }
        return nil;
    },
};

var IDLE = "idle";
var MOVING = "moving";
var BUSY = "busy";

var VehicleComponent = {
    
    new: func(type,aiid) {	    
	    var obj = { parents: [VehicleComponent] };
	    obj.state = IDLE;
	    obj.statechangetimestamp = 0;
	    obj.type = type;
	    # lastdestination is a GraphNode
	    obj.lastdestination=nil;
	    obj.path = nil;
	    obj.aiid = aiid;
		return obj;
	},
	
	expiredIdle: func(maxidletime) {
	    #logging.debug("currentstate is "~me.state);
	
        if (me.state != IDLE){
            return 0;
        }
        if (me.statechangetimestamp + maxidletime < systime()) {
            return 1;
        }
        return 0;
    },
            
    setStateMoving: func( path) {
        logging.info("vehicle "~me.aiid~" starts moving on path " ~ path.toString());    
        me.state = MOVING;
        me.statechangetimestamp = systime();
        me.path = path;
    },
    
    setStateIdle: func() {
        me.state = IDLE;
        me.path = nil;
        me.statechangetimestamp = systime();
    },    
    
    setStateBusy: func() {
        me.state = BUSY;
    },
        
    isMoving: func() {
        return me.path;
    } ,       	    	        	
};

logging.debug("completed GroundVehicle.nas");

