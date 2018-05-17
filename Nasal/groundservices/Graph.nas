#
#
#

logging.debug("executing Graph.nas");

var pathcache = {};

var Graph = {
    
    new: func(orientation) {	    
	    var obj = { parents: [Graph] };
		#obj.nodesList = List.new();
		#obj.edgesList = List.new();
		obj.nodes = [];
        obj.edges = [];
        obj.smoothing = nil;
        obj.orientation = orientation;
        return obj;
	},
	
	addNode: func(name, locationXYZ) {
        return GraphNode.new(me.nodes, name, locationXYZ);
    },
         
    connectNodes: func(from, to, edgename = "", layer=0) {
        #logging.debug("connectNodes from " ~ from.getName() ~ from.getLocation().toString() ~ " to " ~ to.getName() ~ to.getLocation().toString());
        
        var edge = GraphEdge.new(from, to, edgename, layer);
        from.addEdge(edge);
        to.addEdge(edge);
        append(me.edges,edge);
        return edge;
    },
    
    getNodeCount: func() {
        return size(me.nodes);#size(me.nodesList);
    },
    
    getNode: func(index) {
        return me.nodes[index];#List.get(index);
    },
    
    getEdgeCount: func() {
        return size(me.edges);
    },
    
    getEdge: func(index) {
        return me.edges[index];#List.get(index);
    },
    
    findNodeByName: func(name) {
        #logging.debug("findNodeByName "~name);
        foreach(var n; me.nodes) {
            if (name == n.getName()) {
                 return n;
            }
        }
        logging.warn("findNodeByName not found: "~name);
        return nil;
    },

    findConnection: func (n1, n2) {
        foreach (var e ; n1.getEdges()) {
            if (e.getFrom() == n2 or e.getTo() == n2) {
                return e;
            }
        }
        return nil;
    },

    getWeight: func(next, v) {
        var e = me.findConnection(next, v);
        return e.getLength();
    },

    findEdgeByName: func(name) {
        foreach (var e ; me.edges) {
            if (name == e.getName()) {
                return e;
            }
        }
        return nil;
    },

    # Return path from from node to to node 
    # Return nil if no path is found.
    findPath: func(fromnode, tonode, graphWeightProvider) {
        #var pathkey = fromnode.getId()~"-"~tonode.getId();
        #if (voidedges != nil){
        #    foreach (var ve ; voidedges){
        #        pathkey ~= "-" ~ ve.getName();
        #    }
        #}
        #if (pathcache[pathkey] != nil){
        #    logging.debug("found pathkey in cache:"~pathkey);
        #    return pathcache[pathkey];
        #}
        if (!contains(tonode,"id")) {
            logging.warn("findPath(): tonode is no graph node");
            return nil;
        }
        var starttime = systime();
        var pf = PathFinder.new(me, fromnode, me.nodes, graphWeightProvider);
        var result = pf.dijkstra(tonode);
        #pathcache[pathkey]=result;
        logging.debug("findPath from " ~ fromnode.getName() ~ " to " ~ tonode.getName() ~ " took " ~ (systime() - starttime) ~ " seconds");
        return result;                                
    },
    
    findNearestNode: func(pXYZ, graphNodeFilter) {
        var best = nil;
        var bestdistance = FloatMAX_VALUE;
        foreach (var n ; me.nodes) {
            var distance = Vector3.getDistanceXYZ(pXYZ, n.getLocation());
            if (distance < bestdistance and (graphNodeFilter == nil or graphNodeFilter.acceptNode(n))) {
                bestdistance = distance;
                best = n;
            }
        }
        return best;
    },
        
    removeLayer: func(layer) {
        var nlist = [];
        foreach (var e ; me.edges) {
            if (e.getLayer() == layer) {
                 e.removeFromNodes();
            } else {
                 append(nlist,e);
            }
        }
        me.edges = nlist;
    },
    
    getStatistic: func() {
        var layercount = {};
        foreach (var e ; me.edges) {
            var layer = e.getLayer();
            if (layercount[layer]==nil) {
                    layercount[layer] = 0;
            }
            layercount[layer] += 1;
        }
        var s="nodes:";
        foreach (var l; keys(layercount)) {
            s ~= ""~l~":"~layercount[l]~";";
        }
        return s;
    },
    
    dumpToLog: func() {
        var index=0;
        foreach (var e ; me.edges) {
        }
        index=0;
        foreach (var n ; me.nodes) {
            logging.debug("node "~index~": "~n.name~"("~n.locationXYZ.toString());
            index +=1;
        }
    },
};

#Dijkstra's algorithm to find shortest path from s to all other nodes
var PathFinder = {    
    new: func( graph, startnode, nodelist, graphWeightProvider) {	    
	    var obj = { parents: [PathFinder] };
	    # GraphNode->float
		obj.dist = {};
        # GraphNode->GraphNode
        obj.pred = {};
        # GraphNode
        obj.unvisited = {};
        # GraphNode
        obj.visited = {};
        obj.graph = graph;
        obj.graphWeightProvider = graphWeightProvider;
        obj.startnode = startnode;
    
        var size = graph.getNodeCount();
        for (var i = 0; i < size; i=i+1) {
            var n = nodelist[i];
            obj.unvisited[n.id] = n;            
            obj.dist[n.id] = FloatMAX_VALUE;
        }
        obj.dist[startnode.id] = 0;
        return obj;
  	},

    dijkstra: func(destinationnode) {
        while (size(me.unvisited) > 0) {
            #logging.debug("unvisited:"~size(me.unvisited));
            var next = me.closestUnvisitedNode();
            if (next == nil) {
                break;
            }
            me.visited[next.id] = next;
            delete(me.unvisited,next.id);
            me.evaluatedNeighbors(next);
        }
        
        var path = []; # GraphNode
        var x = destinationnode;
        while (x != me.startnode) {
            if (validateObject(x,"x","GraphNode")) {
                logging.error("validate of x failed");
                return nil;
            }
            insertIntoList(path, 0, x);            
            x = me.pred[x.id];
            if (x == nil) {
                #no predecssor->no path
                return nil;
            }
        }
        var p = GraphPath.new(-1);
        var current = me.startnode;
        foreach (var n ; path) {
            p.addSegment(GraphPathSegment.new(me.graph.findConnection(current, n),current));
            current = n;
        }
        return p;
    },

    evaluatedNeighbors: func( n) {
        var neighbors = n.getNeighbors();
        foreach (var neighbor ; neighbors) {
            if (!contains(me.visited,neighbor.id)) {
                var totaldistance = me.dist[n.id] + me.getWeight(n, neighbor);
                if (me.dist[neighbor.id] > totaldistance) {
                    me.dist[neighbor.id] = totaldistance;
                    me.pred[neighbor.id] = n;
                }
            }
        }
    },

    getWeight: func( n1,  n2) {
        if (me.graphWeightProvider != nil) {
            return me.graphWeightProvider.getWeight(n1, n2);
        }
        return me.graph.getWeight(n1, n2);
    },

    closestUnvisitedNode: func() {
        var x = FloatMAX_VALUE;
        var fn = nil;
        foreach (var nid ; keys(me.unvisited)) {
            var n = me.unvisited[nid];
            if ( me.dist[n.id] < x) {
                fn = n;
                x = me.dist[n.id];
            }
        }
        return fn;
    }
};

var graphedgeuniqueid = 1;

var GraphEdge = {
    
    new: func(from, to, name, layer) {	    
	    var obj = { parents: [GraphEdge] };
	    obj.id = graphedgeuniqueid;
        graphedgeuniqueid += 1;        		
		obj.from = from;
		obj.to = to;
		obj.name = name;
		obj.layer = layer;
		obj.dir = to.getLocation().subtract(from.getLocation());
        obj.len = to.getLocation().subtract(from.getLocation()).length();
        # unused obj.customdata = nil;
        # GraphArc
        obj.arcParameter = nil;
        if (obj.checklen()){
            #logging.debug("len problem with "~from.getName()~":"~from.getLocation().toString()~" "~to.getName()~":"~to.getLocation().toString());
        }
		return obj;
	},
	
	getTo: func(){
        return me.to;
    },
    
    getFrom: func(){
        return me.from;
    },      
    
    getLength: func() {
        return me.len;
    },
    
    # angle is radian (former setArc() function)
    setArcAtFrom: func(center, radius, angle, normal) {
        var ex = me.from.getLocation().subtract(center);
        me.setArc(GraphArc.new(center, radius, ex, normal, angle));
    },

    setArc: func(grapharc) {
        me.arcParameter = grapharc;
        var umfang = 2 * PI * grapharc.getRadius();
        me.len = abs(umfang * grapharc.beta / (2 * PI));
        if (me.checklen()){
            logging.debug("len problem with radius " ~ grapharc.getRadius());
        }
    },
            
    checklen: func() {
        if (me.len < 0.000001){
            logging.warn(me.name~": adjusting too low len to 0.000001");
            me.len = 0.000001;
            return 1;
        }
        if (me.len > 1000000){
            logging.warn("adjusting too large len to 100");
            me.len = 100;
            return 1;
        }
        return 0;
    },
        
    get3DPosition: func(edgeposition) {
        if (me.arcParameter == nil) {
            #line
            return me.from.getLocation().add(me.dir.multiply(edgeposition / me.len));
        }
        #arc
        #var rot = buildRotationZ(degreeFromRadians(me.angle * edgeposition / me.len));
        #8.5.18 var resultXYZ = me.vf.rotate(rot);
        #resultXYZ = resultXYZ.add(me.center);
        var resultXYZ = me.arcParameter.getRotatedEx(edgeposition / me.len, 0);
        resultXYZ = me.arcParameter.arccenter.add(resultXYZ);
        #logger.debug("resultXYZ="~resultXYZ.toString()~" for position "~edgeposition);            
        return resultXYZ;
    },
    
    getCenter: func() {
        if (me.arcParameter == nil) {
            return nil;
        }
        return me.arcParameter.arccenter;
    },
    
    getDirection:func () {
        return me.dir;
    },
    
    getEffectiveDirection: func( edgeposition) {
        if (me.arcParameter == nil) {
            # line. trivial.
            return me.dir.normalize();
        }
        #var degree = (me.angle < 0) ? -90 : 90;
        #8.5.18 var dir = rotateXY(me.vf.x,me.vf.y, radianFromDegree(degree));
        #var rotangle = me.angle * edgeposition / me.len;
        #logging.debug("getEffectiveDirection: rotangle="~rotangle~",len="~me.len);
        #8.5.18 dir = rotateXY(dir.x,dir.y,rotangle);
        #var arcdir = Vector3.new(dir.x,dir.y,0);
        #return arcdir.normalize();
        var v = me.arcParameter.getRotatedEx(edgeposition / me.len, 0);
        if (me.arcParameter.getBeta() < 0) {
            v = Vector3.getCrossProduct(v, me.arcParameter.n).normalize();
        } else {
            v = Vector3.getCrossProduct(me.arcParameter.n, v).normalize();
        }
        return v;                
    },
    
    getEffectiveBeginDirection: func() {
        return me.getEffectiveDirection(0);
    },
    
    getEffectiveEndDirection: func() {
        return me.getEffectiveDirection(me.len);
    },

    getEffectiveInboundDirection: func(node) {
        return me.getEffectiveOutboundDirection(node).negate();
    },
        
    # "node" is not checked for validness.
    # normalized.
    getEffectiveOutboundDirection: func(node) {
        var effectivedir = nil;
        if (me.from == node) {
            effectivedir = me.getEffectiveBeginDirection();
        } else {
            effectivedir = me.getEffectiveEndDirection().negate();
        }
        return effectivedir;
    },
    
    getAngleBetweenEdges: func(i, node, o) {
        return Vector3.getAngleBetween(i.getEffectiveInboundDirection(node), o.getEffectiveOutboundDirection(node));
    },
    
    getName: func() {
        return me.name;
    },
    
    setName: func( name) {
        me.name = name;
    },

    equals: func(e) {
        return e.id == me.id;
    },
              
    getOppositeNode: func(node) {
        if (node == me.from) {
            return me.to;
        }
        return me.from;
    },
	
	getId: func() {
        return me.id;
    },
    
    getLayer: func() {
        return me.layer;
    },
        
    removeFromNodes: func() {
        me.removeFromNode(me.from);
        me.removeFromNode(me.to);
    },
        
    removeFromNode: func(n) {
        var nlist = [];
        foreach (var e ; n.edges) {
            if (e != me) {
                append(nlist,e);
            }
        }
        n.edges = nlist;
    },
            
	toString: func(){
	    #return me.name ~ " from " ~ me.from.toString() ~ " to " ~ me.to.toString() ~ ", len=" ~ me.len; 
	    return me.getName() ~ "(" ~ me.from.getName() ~ "->" ~ me.to.getName() ~ ")";
	},
	
    isArc: func() {
        return me.arcParameter != nil;
    },
    
    getArc: func() {
        return me.arcParameter;
    },
    
    # Return the node connecting this edge to "e".
    getNodeToEdge: func(e) {
        if (me.from.findEdge(e) != nil) {
            return me.from;
        }
        if (me.to.findEdge(e) != nil) {
            return me.to;
        }
            return nil;
    },
};


var graphnodeeuniqueid = 1;

var GraphNode = {
    
    new: func(nodes, name, locationXYZ) {	    
	    var obj = { parents: [GraphNode] };
	    obj.id = graphnodeeuniqueid;
	    graphnodeeuniqueid += 1;
		obj.name = name;
		obj.locationXYZ = locationXYZ;
		obj.edges = [];
		obj.altneedsupdate = 1;
		obj.customdata = nil;
		#optional GraphNode, eg. for outlined nodes        
        obj.parent = nil;
		append(nodes,obj);
		return obj;
	},
	getLocation: func() {
        return me.locationXYZ;
    },
    getName: func(){
        return me.name;
    },
    getEdges: func(){
        return me.edges;
    },
    addEdge:func(edge){
        append(me.edges,edge);
    },
    getEdgeCount: func() {
        return size(me.edges);
    },
    getEdge: func(index) {
        return me.edges[index];
    },
    # returns array of GraphEdge
    getEdgesExcept: func(edge) {
        var l = [];
        foreach (var e; me.edges){
            if (e != edge) {
                append(l,e);
            }
        }
        return l;
    },

	getName: func() {
        return me.name;
    },
    
	getNeighbors: func() {
        var neighbors = [];
        foreach (var e; me.edges) {
            append(neighbors,e.getOppositeNode(me));
        }
        return neighbors;
    },

    getId: func() {
        return me.id;
    },
    
    equals: func(e) {
        return e.id == me.id;
    },
        
    toString: func(){
	    return me.name ; 
	},
	
	findEdge: func(edge) {
        foreach (var e ; me.edges) {
            if (e.equals(edge)) {
                return e;
            }
        }
        return nil;
    },
};

var GraphPosition = {
    
    new: func(edge, edgeposition=0, reverseorientation=0) {	    
	    var obj = { parents: [GraphPosition] };
		obj.currentedge = edge;
		obj.edgeposition = edgeposition;
		obj.reverseorientation = reverseorientation;
		obj.reversegear = 0;
		if (edge == nil) {
		    logging.warn("edge is nil");
		}
		return obj;
	},
	
	get3DPosition: func() {
	    if (me.reverseorientation) {
            return me.currentedge.get3DPosition(me.currentedge.getLength()-me.edgeposition);
        }
        return me.currentedge.get3DPosition(me.edgeposition);	    
	},
     	
    isReverse: func() {
        return me.reverseorientation;
    },
    
    toString: func(){
        return "" ~ me.currentedge.toString() ~ "@" ~ ((me.reverseorientation) ? "-" : "") ~ me.edgeposition;
    },

    getAbsolutePosition: func() {
        var absoluteedgeposition=me.edgeposition;
        if (me.reverseorientation){
            absoluteedgeposition=me.currentedge.getLength()-me.edgeposition;
        }
        return absoluteedgeposition;
    },
    
    getNodeInDirectionOfOrientation: func() {
        if (me.reverseorientation){
            return me.currentedge.getFrom();
        }
        return me.currentedge.getTo();
    },
};

var GraphPath = {    
    new: func(layer) {	    
	    var obj = { parents: [GraphPath] };
	    obj.layer = layer;
	    # list of GraphPathSegment
	    obj.path = [];
	    obj.startposition = nil;
	    obj.backward = 0;
	    obj.finalposition = nil;
	    return obj;
	},
        
    addSegment: func( segment) {
        #logging.debug("adding "~segment.toString());
        append(me.path,segment);
    },
        
    getSegmentCount: func() {
        return size(me.path);
    },
        
    getSegment:func (index) {
        return me.path[index];
    },
        
    #start looking at "from" (excepting from).
    getNearestLineEdge: func(from) {
        var nearestlineedge = nil;
        var foundfrom = (from == nil);
        for (var i = 0; i < me.getSegmentCount(); i=i+1) {
            var e = me.getSegment(i);
            if (e.getCenter() == nil) {
                if (foundfrom) {
                    return e;
                }
                if (from != nil and e == from) {
                    foundfrom = 1;
                }
            }
        }
        return nearestlineedge;
    },
        
    getLast: func() {
        return me.getSegment(me.getSegmentCount() - 1);
    },
    
    insertSegment: func( index,  segment) {
        insertIntoList(me.path,index,segment);
    },
    
    toString: func(detailed=0) {
        var s = "";
        if (me.startposition != nil and me.backward) {
            s = s ~ "[back on " ~ me.startposition.currentedge.getName() ~ "]";
        }                 
        if (size(me.path) == 0) {
            return s;
        }
        s ~= me.getStart().getName() ~ ":";                
        s ~= me.path[0].edge.getName();
        for (var i = 1; i < size(me.path); i+=1) {
            var edge = me.path[i].edge;
            var edgename = edge.getName();
            var arcpara = edge.getArc();
            if (detailed and arcpara != nil and arcpara.origin != nil) {
                edgename = edgename ~ "@" ~ arcpara.origin.getName();
            }
            var nodetag = "->";
            if (detailed) {
                var enternode = me.path[i].getEnterNode();
                nodetag = "--" ~ enternode.getName();
                if (enternode.parent != nil) {
                    nodetag ~= "@" ~ enternode.parent.getName();
                }
                nodetag ~= "-->";
            }
            s ~= nodetag ~ edgename ~ "(" ~ math.round(edge.getLength()) ~ ")";
        }
        return s;
    },
    
    replaceLast: func( transition) {
        #var index = size(me.path) - 1;
        #me.path[index] = transition.seg[0];        
        #for (var i=1;i<size(transition.seg);i+=1) {
        #    append(me.path,transition.seg[i]);
        #}
        if (size(me.path) > 0) {
            me.path = removeFromList(me.path,size(me.path) - 1);        
        }
        foreach (var s ; transition.seg) {
            append(me.path,s);
        }
    },
    
    getLength: func(currentposition) {
        var len = 0;
        for (var i = me.getSegmentCount() - 1; i>=0;i=i-1) {
            var e = me.getSegment(i).edge;
            if (currentposition!=nil and e == currentposition.currentedge) {
                len += currentposition.currentedge.getLength()-currentposition.edgeposition;
                return len;
            }
            len += e.getLength();
        }
        return len;
    },
    
    getStart: func() {
        return me.path[0].getEnterNode();
    },
    
    getDetailedString: func () {
        return me.toString(true);
    },
        
    validateAltitude: func() {
        for (var i = 0; i<me.getSegmentCount() ; i=i+1) {
            var e = me.getSegment(i).edge;
            if (validateAltitude(e.from.locationXYZ.z)) {
                logging.warn("out of range altitude in edge.from "~e.from.toString());
            }
            if (validateAltitude(e.to.locationXYZ.z)) {
                logging.warn("out of range altitude in edge.to "~e.to.toString());
            }
        }
    },
};


var GraphPathSegment = {    
    new: func( edge, enternode) {	    
	    var obj = { parents: [GraphPathSegment] };
	    obj.edge = edge;
	    obj.enternode = enternode;
	    obj.changeorientation = 0;
	    return obj;
    },

    getLeaveNode: func() {
        return me.edge.getOppositeNode(me.enternode);
    },
    
    getEnterNode: func() {
        return me.enternode;
    },
    
    toString: func() {
        return me.edge.toString();
    },
};

var GraphTransition = {    
    new: func( s0=nil,s1=nil,s2=nil) {	    
	    var obj = { parents: [GraphTransition] };
	    obj.seg = [];
	    if (s0 != nil)
	        append(obj.seg,s0);
	    if (s1 != nil)
        	append(obj.seg,s1);
        if (s2 != nil)
        	append(obj.seg,s2);
	    return obj;
    },
    
    add: func(graphPathSegement) {
        append(me.seg,graphPathSegement);
    },
    
    toString: func() {
        var s = "Transition:";
        foreach (var se; me.seg) {
            s ~= se.toString() ~ ",";
        }
        return s;
    },
};

var DefaultGraphWeightProvider = {    
    new: func( graph, validlayer, voidedges = nil) {	    
	    var obj = { parents: [DefaultGraphWeightProvider] };
	    obj.graph = graph;
	    # me.validlayer is int array, parameter is int
	    obj.validlayer = [validlayer];
	    if (voidedges == nil) {
	        obj.voidedges = [];
	    } else {
	        logger.debug("Building DefaultGraphWeightProvider with "~size(voidedges)~" void edges");
	        obj.voidedges = voidedges;
	    }
	    return obj;
    },
    
    getWeight: func(n1, n2) {                
        if (me.voidedges != nil) {
            foreach (var e; me.voidedges) {
                if (e.from == n1 and e.to == n2) {
                    return FloatMAX_VALUE;
                }
                if (e.to == n1 and e.from == n2) {
                    return FloatMAX_VALUE;
                }
            }
        }
        var e1 = me.graph.findConnection(n1, n2);
        if (!me.isvalid(e1.getLayer())) {
            return FloatMAX_VALUE;
        }
        return me.graph.getWeight(n1, n2);
    },
    
    isvalid: func( layer) {
        if (me.validlayer == nil) {
            return 1;
        }
        foreach (var l; me.validlayer) {
            if (l == layer) {
                return 1;
            }
        }
        return 0;
    }
};

#Graph extension for Teardrop, turnloop, back, etc.
var TurnExtension = {    
    new: func(edge, branch, arc) {	    
	    var obj = { parents: [TurnExtension] };
	    obj.edge = edge;
	    obj.branch = branch;
	    obj.arc = arc;
	    return obj;
    },

    # Same for branch and arc (but not edge).
    getLayer: func() {
        if (me.branch!=nil) {
            return me.branch.getLayer();
        }
        if (me.edge!=nil) {
            return me.edge.getLayer();
        }
        if (me.arc!=nil) {
            return me.arc.getLayer();
        }
        return -1;
    },
};

var GraphArc = {    
    new: func(arccenter, radius, ex, n, beta) {	    
	    var obj = { parents: [GraphArc] };
	    obj.arccenter = arccenter;
	    obj.radius = radius;
	    obj.ex = ex.normalize();
	    obj.n = n.normalize();
	    # beta in radians
	    obj.beta = beta;
	    #origin GraphNode 
	    obj.origin = nil;
	    return obj;
    },
    
    # Effective rotated e Vector between ex (t=0) and ey (t=1).
    getRotatedEx: func(t) {
        var e1 = me.ex;
        var z2n = Quaternion.buildQuaternion(Vector3.new(0, 0, 1), me.n);
        var n2z = Quaternion.buildQuaternion(me.n, Vector3.new(0, 0, 1));
        var angle = -me.beta;
        var rotated = e1.rotate(n2z);
        rotated = rotated.rotate(buildQuaternionFromAngles(0, 0, -angle * t));
        rotated = rotated.rotate(z2n);
        rotated = rotated.multiply(me.radius);
        return rotated;
    },
    
    getRadius: func() {
        return me.radius;
    },
    
    getBeta: func() {
        return me.beta;
    },
};

# abstract class
var GraphOrientation = {    
	new: func() {	    
	    var obj = { parents: [GraphOrientation] };
	    return obj;
	},
   
    buildForZ0: func() {return GraphOrientationZ0.new();},
    buildDefault: func() {return GraphOrientationDefault.new();},
    buildForFG: func() {return GraphOrientationFG.new();},
        
    get3DRotation: func(reverseorientation, effectivedirection, edge) {        
        if (reverseorientation) {
            effectivedirection = effectivedirection.negate();
        }

        var forwardrotation = me.getForwardRotation();
        var up = me.getUpVector(edge);
        var rotation = Quaternion.buildLookRotation(effectivedirection.negate(), up);
        var localr = Quaternion.new();
        return localr.multiply(rotation).multiply(forwardrotation);            
    },
    
    # Outline along a graph.
    getOutline: func(path, offset, layer) {
        var lastnode = nil;
        var edge = nil;;
        if (path != nil and size(path) == 1 and path[0].edge.getArc() != nil) {
            var arcsegment = path[0];
            edge = arcsegment.edge;
            lastnode = arcsegment.getLeaveNode();
            if (lastnode != nil and edge.getArc() != nil) {
                return buildArcOutline(edge, offset, 16, arcsegment.getEnterNode().equals(edge.getTo()));
            }
        }

        var line = [];
        if (size(path) == 0) {
            return line;
        }

        var startnode = nil;
        var idx = 0;

        edge = path[0].edge;
        idx+=1;
        startnode = path[0].enternode;

        # first point
        var rotation = nil;
        var dir = edge.getEffectiveOutboundDirection(startnode);        
        var offsettouse = me.getOffsetToUse(edge, offset, layer);
        var outpoint = me.getEndOutlinePoint(startnode, edge, dir, offsettouse);
        append(line,outpoint);


        while (edge != nil) {
            var nextnode = edge.getOppositeNode(startnode);
            if (nextnode == nil) {
                #circle?
                break;
            }
            if (path != nil and idx > size(path)) {
                break;
            }
            
            var nextdir = nil;
            var nextedge = nil;
            if (idx < size(path)) {
                nextedge = path[idx].edge;
                idx+=1;
            }
            if (nextedge != nil) {
                nextdir = nextedge.getEffectiveOutboundDirection(nextnode);
                var angle = degreeFromRadians(Vector3.getAngleBetween(dir, nextdir) / 2);
                var kp = nil;
                if (angle > 0.05) {
                    kp = Vector3.getCrossProduct(dir, nextdir).normalize();
                }
                               
                offsettouse = offset;
                if (layer != -1 and (edge.getLayer() != layer or nextedge.getLayer() != layer)) {
                    offsettouse = 0;
                }
                var offsetv = nil;
                if (kp == nil) {
                    #dir/nextdir parallel
                    rotation = Quaternion.buildQuaternionFromAngleAxis(angle, me.getUpVector(edge));
                    offsetv = Vector3.getCrossProduct(dir, me.getUpVector(edge));
                } else {
                    rotation = Quaternion.buildQuaternionFromAngleAxis(angle, kp);
                    offsetv = Vector3.getCrossProduct(dir, me.getUpVector(edge));
                }
                offsetv = offsetv.normalize().multiply(offsettouse);
                var outlinepoint = nextnode.getLocation().add(offsetv.rotate(rotation));
               
                append(line,outlinepoint);
                #logger.debug("outline at " + nextnode.getLocation() + " is " + outlinepoint + " with angle " + angle);
            } else {
                # last point
                dir = edge.getEffectiveInboundDirection(nextnode);
                offsettouse = me.getOffsetToUse(edge, offset, layer);
                outpoint = me.getEndOutlinePoint(nextnode, edge, dir, offsettouse);
                append(line,outpoint);
            }
            # prepare next step
            dir = nextdir;
            edge = nextedge;
            startnode = nextnode;
        }        
        return line;
    },

    getOffsetToUse:func (edge, offset, layer) {
        var offsettouse = offset;
        if (layer != -1 and edge.getLayer() != layer) {
            offsettouse = 0;
        }
        return offsettouse;
    },

    getOutlineFromNode: func(basenode, offset) {
        var startnode = basenode;
        var edge = startnode.getFirstFromEdge();
        var path = [];
        append(path,GraphPathSegment.new(edge, startnode));
        while (edge != nil) {
            var nextnode = edge.getOppositeNode(startnode);
            if (nextnode == basenode) {
                #circle?
                break;
            }
            var nextedge = nil;
            var nextedges = nextnode.getEdgesExcept(edge);
            if (size(nextedges) == 1) {
                nextedge = nextedges[0];
                append(path,GraphPathSegment.new(nextedge, nextnode));
            } 
            edge = nextedge;
            startnode = nextnode;
        }
        return me.getOutline(path, offset, -1);
    },

    getEndOutlinePoint: func(node, edge, dir, offset) {
        var outv = Vector3.new(offset, 0, 0);
        var reverseorientation = false;
        var rotation = me.get3DRotation(reverseorientation, dir, edge);
        return node.getLocation().add(outv.rotate(rotation));
    },

    buildArcOutline: func(edge, offset, segments, reverse) {
        var p = edge.getArc();
        var line = [];

        var center = edge.getCenter();
        var step = 1.0 / segments;

        var index = 0;
        for (var i = 0; i <= segments; i+=1) {
            index = i;
            if (reverse) {
                index = segments - i;
            }
            var v = p.getRotatedEx(index * step, 0);
            v = v.normalize().multiply(p.getRadius() - (reverse ? -1 : 1) * offset);
            v = center.add(v);
            append(line,v);
        }
        return line;
    },
};

# upVector  (0,0,1)
var GraphOrientationZ0 = {    
	new: func() {	    
	    var obj = { parents: [GraphOrientationZ0,GraphOrientation.new()] };
	    return obj;
	},
    
    getForwardRotation: func() {
        return Quaternion.new();
    },

    getUpVector: func(edge) {
        var up = Vector3.new(0, 0, 1);        
        return up;
    },
};

# upVector  (0,1,0)
var GraphOrientationDefault = {    
	new: func() {	    
	    var obj = { parents: [GraphOrientationDefault,GraphOrientation.new()] };
	    return obj;
	},

    getForwardRotation: func() {
        var rotation = Quaternion.new();
        return rotation;
    },

    getUpVector: func(edge) {
        var up = Vector3.new(0, 1, 0);        
        return up;
    },
};

var GraphOrientationFG = {    
	new: func() {	    
	    var obj = { parents: [GraphOrientationFG,GraphOrientation.new()] };
	    return obj;
	},

    getForwardRotation: func() {
        var rotation = Quaternion.buildQuaternionFromDegrees(-90, -90, 0);
        return rotation;
    },

    getUpVector: func(edge) {
        var up = edge.from.getLocation().normalize();
        var baserotation = Quaternion.new();
        return up.rotate(baserotation);
    },    
};

var buildPositionAtNode = func( edge,  node,  intoedge) {
    if (edge.from == node) {
        if (intoedge) {
            return GraphPosition.new(edge);
        } else {
            return GraphPosition.new(edge, edge.getLength(), 1);
        }
    }
    if (intoedge) {
        return GraphPosition.new(edge, 0, 1);
    } else {
        return GraphPosition.new(edge, edge.getLength(), 0);
    }
};


    
logging.debug("completed Graph.nas");