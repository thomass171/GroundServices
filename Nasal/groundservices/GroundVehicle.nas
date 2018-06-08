#
# The global id is assigned here
#

logging.debug("executing GroundVehicle.nas");

var baseid = 5567;
var lastlogsecond = 0;
var graphmovementdebuglog = 1;


var GroundVehicle = {
	new: func(model, gmc, maximumspeed, type, delay, zoffset, modeltype) {
	    logging.debug("new GroundVehicle. model="~model);
		#props.globals.getNode("gear/gear[0]/wow", 1).setValue(1);
		#props.globals.getNode("sim/model/pushback/enabled", 1).setValue(1);

		var m = { parents: [GroundVehicle] };
		m.interval = 10;
		m.coord = geo.Coord.new();
		m.gmc = gmc;
		m.delay = delay;

        # create node in "/models" for having the vehicle model updated(repositioned) by core FG.
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
        
        m.ai.getNode("id", 1).setIntValue(m.aiid);
		m.ai.getNode("vehicle", 1).setBoolValue(1);
		m.ai.getNode("valid", 1).setBoolValue(1);
        m.ai.getNode("type", 1).setValue(type);         		
        m.ai.getNode("zoffset", 1).setDoubleValue(zoffset);
        
		m.latN = m.ai.getNode("position/latitude-deg", 1);
		m.lonN = m.ai.getNode("position/longitude-deg", 1);
		m.altN = m.ai.getNode("position/altitude-ft", 1);
		m.hdgN = m.ai.getNode("orientation/true-heading-deg", 1);
		m.hdgN = m.ai.getNode("orientation/true-heading-deg", 1);
        m.zoffsetN = m.ai.getNode("zoffset", 1);
        var maximumspeedN = m.ai.getNode("maximumspeed", 1);		
        maximumspeedN.setValue(maximumspeed);
        var speedN = m.ai.getNode("velocities/speed-ms", 1);
        
        m.vhc = VehicleComponent.new(type,m.aiid,modeltype);
        m.vc = VelocityComponent.new(maximumspeedN, speedN);

		#m.update();
		
		#probe model file in addon. If it exists, use the addon file. Otherwise from FG_ROOT
		var modelpath = root ~ "/" ~ model;
        if (!fileExists(modelpath)) {
             modelpath = fgroot ~ "/" ~ model;        
        }
		
		# link nodes from current "/ai/models/gsvehicle" to corresponding "/models/model[]" entry                
		# avoid model collisions by disabling "enable-hot"
        m.model.getNode("enable-hot", 1).setValue(0);
		m.model.getNode("path", 1).setValue(modelpath);
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
		#logging.debug("del");
		me.model.remove();
		me.ai.remove();
		delete(GroundVehicle.active, me.aiid);
		#tanker_msg("vehicle " ~ me.aiid ~ " removed");        		
	},
	update: func(deltatime) {
	    var currenttime = systime();
	    # rounding problem?
	    if (lastlogsecond != currenttime){
	        lastlogsecond = currenttime;
	        #logging.debug("update");
	    }
	    
	    if (currenttime > me.gmc.statechangetimestamp + me.delay) {
		    me.moveForward(deltatime);
		    me.delay = 0;
		}		       
	},
	
	setPositionFromXY: func(posXY){
	    var coord = projection.unproject(posXY);
	    #logging.debug("setPositionFromXY: x=" ~ posXY.x ~ ",y=" ~ posXY.y ~ ",lat=" ~ coord.lat() ~ ",lon=" ~ coord.lon());
	    me.latN.setDoubleValue(coord.lat());
        me.lonN.setDoubleValue(coord.lon());
        return coord;
	},
	
	moveForward: func(tpf) {
        var gmc = me.gmc;
        var vhc = me.vhc;
        var vc = me.vc;
        
        if (gmc.automove) {
            me.adjustSpeed(gmc, vc, tpf);
            vc.speedN.setValue(vc.movementSpeed);
            var amount= tpf * vc.movementSpeed;
            #logging.debug("moveForward by "~amount);
            var completedpath = gmc.moveForward(amount);
            me.adjustVisual(gmc);
            if (completedpath != nil) {
                vc.setMovementSpeed(0);
                #now in update groundnet.groundnetgraph.removeLayer(completedpath.layer);
                sendEvent({type:GRAPH_EVENT_PATHCOMPLETED, vehicle: me, path:completedpath});
            }  
        }                          
    },
    
    adjustSpeed: func(gmc, vc, deltatime) {
        var left = gmc.getRemainingPathLen();
        var needsbraking = 0;
        var needsspeedup = 0;
        var speedlimit = vc.getMaximumSpeed();

        if (gmc.currentposition.currentedge.isArc() and gmc.currentposition.currentedge.arcParameter.radius < 15) {
            speedlimit = vc.getMaximumSpeed() / 2;
        }

        # avoid swinging between two values
        if (vc.getMovementSpeed() > speedlimit + 1) {
            needsbraking = 1;
        }
        var breakingdistance = vc.getBrakingDistance();#10;
        if (left < breakingdistance) {
            logging.debug("brake due to left " ~ left~", deltatime=" ~ deltatime);
            needsbraking = 1;
        }
        #accelerate?
        if (left > breakingdistance) {
            if (vc.getMovementSpeed() < speedlimit - 1) {
                needsspeedup = 1;
            }
        }

        if (needsbraking) {
            vc.accelerate(-deltatime);
        }
        if (needsspeedup) {
            vc.accelerate(deltatime);
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
        #logging.debug("updating vehicle altitude to " ~ alt ~ ", fromalt="~fromalt~", toalt="~toalt~",edge="~cp.currentedge.toString());
        if (validateAltitude(alt)) {
            logging.warn("updating vehicle to out of range altitude " ~ alt ~ ", fromalt="~fromalt~", toalt="~toalt~",edge="~cp.currentedge.toString());
        }
        var zoffset = me.zoffsetN.getValue();
        alt += zoffset;
        me.altN.setDoubleValue(alt * M2FT);
        
    },
	
	report: func {
		#me.out_of_range_time = me.now;
		#var dist = int(me.distance * M2NM);
		#var hdg = getprop("orientation/heading-deg");
		#var diff = (me.coord.alt() - me.ac.alt()) * M2FT;
		#var qual = diff > 3000 ? " well" : abs(diff) > 1000 ? " slightly" : "";
		#var rel = diff > 1000 ? " above" : diff < -1000 ? " below" : "";
		var statemsg = "idle";
		if (me.vhc.isScheduled()) {
		    statemsg = "busy";
		}
		if (me.gmc.isMoving() != nil) {
		    # might override "busy" 
		    statemsg = "moving to node " ~ ((me.vhc.lastdestination!=nil)?me.vhc.lastdestination.getName():"");
		}
		var msg = sprintf("GroundVehicle [%d] %s %s %s",me.ai.getIndex(),me.vhc.type,me.aiid,statemsg);
		#no longer use atc msg because of spoken atc
		#atc_msg(msg);
		# also report to log file, because atc messages might vanish quickly
		logging.info(msg);
	},
	
	initStatechangetimestamp: func(offset) {
	    me.vhc.statechangetimestamp = systime() - offset;
	    me.gmc.statechangetimestamp = systime() - offset;
	},
	
	active: {},
};

var GraphMovingComponent = {
    
    new: func(dummy1, dummy2, currentposition,unscheduledmoving=1) {	    
	    var obj = { parents: [GraphMovingComponent] };
		obj.currentposition = currentposition;
		obj.automove = 0;
		obj.path = nil;
		obj.selector = nil;
		obj.statechangetimestamp = 0;
		obj.unscheduledmoving = unscheduledmoving;
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
        var pathcompleted = nil; 
        if (me.currentposition.reversegear) {
            amount = -amount;
        }
        if (amount > 0) {
            me.currentposition.edgeposition += amount;
            while (me.currentposition.edgeposition > me.currentposition.currentedge.len) {
                var switchnode = (me.currentposition.reverseorientation) ? me.currentposition.currentedge.from : me.currentposition.currentedge.to;
                var newsegment = me.selector.findNextEdgeAtNode(me.currentposition.currentedge, switchnode);
                if (newsegment == nil) {
                    me.currentposition.edgeposition = me.currentposition.currentedge.len;
                    if (me.path != nil) {
                        pathcompleted = me.movepathCompleted();
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
                        pathcompleted = me.movepathCompleted();
                    }
                } else {
                    me.adjustPositionOnNewEdge(switchnode, newsegment, math.abs(me.currentposition.edgeposition));
                }
            }
        }
        return pathcompleted;
    },

    isMoving: func() {
        if (0 and graphmovementdebuglog) {
            if (me.path == nil) {
                logging.debug("isMoving returning nil");
            } else {
                logging.debug("isMoving returning path");
            }
        }    
        return me.path;
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
            logging.debug("move path completed at " ~ me.currentposition.toString());
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
    
    getRemainingPathLen: func() {
        if (me.path == nil){
            return FloatMAX_VALUE;
        }
        return me.path.getLength(me.currentposition);
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

var VEHICLE_AIRCRAFT = "aircraft";
var VEHICLE_PUSHBACK = "pushback";
var VEHICLE_STAIRS = "stairs";
var VEHICLE_FUELTRUCK = "fueltruck";
var VEHICLE_CATERING = "catering";

var VehicleComponent = {
    
    new: func(type,aiid,modeltype) {	    
	    var obj = { parents: [VehicleComponent] };
	    obj.statechangetimestamp = 0;
	    obj.type = type;
	    # lastdestination is a GraphNode
	    obj.lastdestination=nil;
	    #obj.path = nil;
	    obj.aiid = aiid;
	    obj.createtimestamp = systime();
	    obj.schedule = nil;
	    obj.config = {type:type,modeltype:modeltype};
		return obj;
	},
		    
    isScheduled: func() {
        return me.schedule != nil;
    },
    
    isIdle: func() {
        return me.schedule == nil;
    }, 	
};

var VelocityComponent = {
    
    new: func(maximumspeedN, speedN) {	    
	    var obj = { parents: [VelocityComponent] };
	    # unit is m/s 
        obj.movementSpeed = 0.0;
        obj.acceleration = 1.0;
        obj.deceleration = 2.5;
        obj.maximumspeedN = maximumspeedN;
        obj.speedN = speedN;
		return obj;
	},
	
    setMovementSpeed: func(movementSpeed) {
        me.movementSpeed = movementSpeed;
    },

    incMovementSpeed: func(offset) {
        me.movementSpeed += offset;
    },

    getMovementSpeed: func() {
        return me.movementSpeed;
    },

    setMaximumSpeed: func(maximumSpeed) {
        me.maximumspeedN.setValue(maximumSpeed);
    },

    setAcceleration: func(acceleration) {
        me.acceleration = acceleration;
        #braking iost stronger tahn accelerate
        me.deceleration = acceleration * 2.5;
    },

    accelerate: func(deltatime) {
        if (deltatime < 0) {
            # no absolute stop, otherwise destination will not be reached
            var diff = me.deceleration * deltatime;
            me.movementSpeed += diff;
            #logging.debug("accelerate:diff=" + diff + ",movementSpeed=" + movementSpeed + ",acceleration=" + acceleration);
            if (me.movementSpeed < 1) {
                me.movementSpeed = 1;
            }
        } else {
            me.movementSpeed += me.acceleration * deltatime;
        }
        #logging.debug("accelerate: speed="~me.movementSpeed);        
    },    

    getMaximumSpeed: func() {
        return me.maximumspeedN.getValue();
    },
    
    getBrakingDistance: func() {
        return 0.5 *  (me.movementSpeed * me.movementSpeed / me.deceleration);
    },
};

# Only return idle vehicles because moving ones cannot relocated (due to unknwon layer)
var findAvailableVehicles = func(vehicletype) {
    var list = [];
    foreach (var v; values(GroundVehicle.active)) {
        var vhc = v.vhc;
        var gmc = v.gmc;
        if (vhc.type == vehicletype and vhc.isIdle() and gmc.isMoving() == nil) {
            append(list,v);
        }
    }
    return list;
};
    
logging.debug("completed GroundVehicle.nas");

