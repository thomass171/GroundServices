#
# The global id is assigned here
#

logging.debug("executing GroundVehicle.nas");

var baseid = 5567;
var lastlogsecond = 0;
var graphmovementdebuglog = 1;


var GroundVehicle = {
	new: func(model, gmc, maximumspeed, type, delay) {
	    logging.debug("new GroundVehicle. model="~model);
		#props.globals.getNode("gear/gear[0]/wow", 1).setValue(1);
		#props.globals.getNode("sim/model/pushback/enabled", 1).setValue(1);

		var m = { parents: [GroundVehicle] };
		m.interval = 10;
		m.coord = geo.Coord.new();
		m.gmc = gmc;
		m.delay = delay;

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
		m.maximumspeedN = m.ai.getNode("maximumspeed", 1);		
        m.maximumspeedN.setValue(maximumspeed);
        
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
	    
	    if (currenttime > me.vhc.createtimestamp + me.delay) {
		    me.moveForward(deltatime);
		}		       
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
            var speed = me.maximumspeedN.getValue();
            gmc.moveForward(deltatime * speed);
            me.adjustVisual(gmc);  
        }                          
    },
    
    # elevation is not unique across an airport and must be updated along with the position.
    # elevation must be taken directly from some nodes z value instead of from some 3D vector calculation.
    adjustVisual: func(gmc) {         
        var cp = gmc.currentposition;            
        var positionXYZ = cp.get3DPosition();
        #logging.debug("3Dposition="~positionXYZ.toString());
        var coord = me.setPositionFromXY(positionXYZ);
        var heading = get3DRotation(coord,cp.edgeposition,cp.reverseorientation,cp.currentedge.getEffectiveDirection( cp.getAbsolutePosition()));
        me.hdgN.setValue(heading);
        # use elevation depending on edge position            
        var fromalt = cp.currentedge.from.getLocation().z;
        var toalt = cp.currentedge.to.getLocation().z;
        var relpos = cp.getAbsolutePosition() / cp.currentedge.getLength();
        var alt = fromalt + ((toalt-fromalt) * relpos);
        #logging.debug("updating vehicle altitude to " ~ alt ~ ", fromalt="~fromalt~", toalt="~toalt);
        me.altN.setDoubleValue(alt * M2FT);
        
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
		obj.statechangetimestamp = 0;
		return obj;
	},
	
	setPath: func (path) {
        logging.debug("setPath");
        me.path = path;
        me.automove = 1;
        me.selector = GraphPathSelector.new(path);
        if (path.startposition != nil) {
            me.currentposition = path.startposition;
            me.currentposition.reversegear = path.backward;
        }
        me.statechangetimestamp = systime();
    },
    	        	
    moveForward: func( amount) {
        #logging.debug("moveForward "~amount ~ ",currentposition="~me.currentposition.toString());    
        if (amount > 0) {
            me.currentposition.edgeposition += amount;
            while (me.currentposition.edgeposition > me.currentposition.currentedge.len) {
                var switchnode = (me.currentposition.reverseorientation) ? me.currentposition.currentedge.from : me.currentposition.currentedge.to;
                var newsegment = me.selector.findNextEdgeAtNode(me.currentposition.currentedge, switchnode);
                if (newsegment == nil) {
                    me.currentposition.edgeposition = me.currentposition.currentedge.len;
                    if (me.path != nil) {
                        me.movepathCompleted();
                    }
                } else {
                    me.adjustPositionOnNewEdge(switchnode, newsegment, me.currentposition.edgeposition - me.currentposition.currentedge.len);
                }
            }
        }

        if (amount < 0) {
            me.currentposition.edgeposition += amount;
            while (me.currentposition.edgeposition < 0) {
                var switchnode = (me.currentposition.reverseorientation) ? me.currentposition.currentedge.to : me.currentposition.currentedge.from;
                var newsegment = me.selector.findNextEdgeAtNode(me.currentposition.currentedge, switchnode);
                if (newsegment == nil) {
                    me.currentposition.edgeposition = 0;
                    if (me.path != nil) {
                        me.movepathCompleted();
                    }
                } else {
                    me.adjustPositionOnNewEdge(switchnode, newsegment, math.abs(me.currentposition.edgeposition));
                }
            }
        }
    },

    adjustPositionOnNewEdge: func(switchnode, newsegment, remaining) {
        var newedge = newsegment.edge;
        if ((switchnode == newedge.to and switchnode == me.currentposition.currentedge.from) or
                (switchnode == newedge.from and switchnode == me.currentposition.currentedge.to)) {
            me.currentposition.reverseorientation = me.currentposition.reverseorientation;
        } else {
            me.currentposition.reverseorientation = !me.currentposition.reverseorientation;
        }
        if (newsegment.changeorientation) {
            me.currentposition.reverseorientation = !me.currentposition.reverseorientation;
        }

        if (newedge.to == switchnode) {
            # entering through to
            if (me.currentposition.reverseorientation) {
                me.currentposition.edgeposition = remaining;
            } else {
                me.currentposition.edgeposition = newedge.len - remaining;
            }
        } else {
            # entering through from
            if (me.currentposition.reverseorientation) {
                #OK
                me.currentposition.edgeposition = newedge.len - remaining;
            } else {
                me.currentposition.edgeposition = remaining;
            }
        }
        me.currentposition.currentedge = newedge;
        me.currentposition.reversegear = 0;
    },
    
    movepathCompleted: func() {
        if (graphmovementdebuglog) {   
            logging.info("move path completed at " ~ me.currentposition.toString());
        }
        
        if (me.path.finalposition != nil) {
            #logging.debug("switching to new current position :" ~ me.path.finalposition);
            me.currentposition = me.path.finalposition;
        }
        var pathforreturn = me.path;
        me.path = nil;
        me.automove = 0;
        me.statechangetimestamp = systime();
        return pathforreturn;        
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
            var segment = me.path.getSegment(index + 1);        
            #logging.debug("findNextEdgeAtNode:" ~ ((edge!=nil)?edge.toString():"nil"));        
            return segment;
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
	    obj.createtimestamp = systime();
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

