#
#
#

logging.debug("executing Graph.nas");

var pathcache = {};

var Graph = {
    
    new: func() {	    
	    var obj = { parents: [Graph] };
		#obj.nodesList = List.new();
		#obj.edgesList = List.new();
		obj.nodes = [];
        obj.edges = [];
        obj.smoothing = nil;
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
            var distance = getDistanceXYZ(pXYZ, n.getLocation());
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
        var p = GraphPath.new(me.startnode, -1);
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
        obj.center = nil;
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
    
    # angle is radian
    setArc: func(center, radius, angle) {
        me.center = center;
        me.radius = radius;
        me.vf = me.from.getLocation().subtract(center);
        me.vt = me.to.getLocation().subtract(center);       
        me.angle = angle;
        var umfang = 2 * math.pi * radius;
        me.len = math.abs((umfang * angle / (2 * math.pi)));
        if (me.checklen()){
            logging.debug("len problem with radius "~radius);
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
        if (me.center == nil) {
            #line
            return me.from.getLocation().add(me.dir.multiply(edgeposition / me.len));
        }
        #arc
        var rot = buildRotationZ(degreeFromRadians(me.angle * edgeposition / me.len));
        var resultXYZ = me.vf.rotate(rot);
        resultXYZ = resultXYZ.add(me.center);
        return resultXYZ;
    },
    
    getCenter: func() {
        return me.center;
    },
    
    getDirection:func () {
        return me.dir;
    },
    
    getEffectiveDirection: func( edgeposition) {
        var referenceback = Vector3.new(0, 0, -1);
    
        if (me.center == nil) {
            # line. trivial.
            return me.dir.normalize();
        }
        var degree = (me.angle < 0) ? -90 : 90;
        var dir = rotateXY(me.vf.x,me.vf.y, radianFromDegree(degree));
        var rotangle = me.angle * edgeposition / me.len;
        #logging.debug("getEffectiveDirection: rotangle="~rotangle~",len="~me.len);
        dir = rotateXY(dir.x,dir.y,rotangle);
        var arcdir = Vector3.new(dir.x,dir.y,0);
        return arcdir.normalize();
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
    
    getName: func() {
        return me.name;
    },
    
    setName: func( name) {
        me.name = name;
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
	
	getAngleBetweenEdges: func(i, node, o) {
        return getAngleBetween(i.getEffectiveInboundDirection(node), o.getEffectiveOutboundDirection(node));
    },
    
    isArc: func() {
        return me.center != nil;
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
    
    toString: func(){
	    return me.name ; 
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
    new: func( start, layer) {	    
	    var obj = { parents: [GraphPath] };
	    obj.start = start;
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
    
    toString: func() {
        var s = "";
        if (me.startposition != nil and me.backward) {
            s = s ~ "[back on "+me.startposition.currentedge.getName()+"]";
        }                 
        s = s ~ me.start.getName() ~ ":";
        if (size(me.path) == 0) {
            return s;
        }
        s ~= me.path[0].edge.getName();
        for (var i = 1; i < size(me.path); i+=1) {
            s ~= "->" ~ me.path[i].edge.getName() ~ "(" ~ math.round(me.path[i].edge.getLength()) ~ ")";
        }
        return s;
    },
    
    replaceLast: func( transition) {
        var index = size(me.path) - 1;
        me.path[index] = transition.seg[0];
        
        for (var i=1;i<size(transition.seg);i+=1) {
            append(me.path,transition.seg[i]);
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
};

var DefaultGraphWeightProvider = {    
    new: func( graph, validlayer) {	    
	    var obj = { parents: [DefaultGraphWeightProvider] };
	    obj.graph = graph;
	    # me.validlayer is int array, parameter is int
	    obj.validlayer = [validlayer];
	    obj.voidedges = [];
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