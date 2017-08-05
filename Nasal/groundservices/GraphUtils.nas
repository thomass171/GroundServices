#
#
#

logging.debug("executing GraphUtils.nas");

var smoothNode = func( graph,  node,  radius,  layer) {
    logging.error("smoothNode should not be used");
    return;
    #logging.debug("smoothing node "~node.getName());
    var smoothing = graph.getSmoothing();
    var arcs = [];
    foreach (var edge ; node.edges) {
        var effectiveincomingdir = edge.getEffectiveInboundDirection(node);
        for (var i = 0; i < size(node.edges); i+=1) {
            var e = node.edges[i];
            if (e != edge) {
                var effectivedir = e.getEffectiveOutboundDirection(node);
                var angle = getAngleBetween(effectiveincomingdir, effectivedir);
                #logging.debug("effectivedir="~effectivedir.toString());
                #logging.debug("angle="~angle);
                                
                if (angle > 0.1 and angle < (math.pi/2) * 1.8) {
                    if (!smoothing.areSmoothed(e, edge)) {
                        append(arcs,addAlternateRouteByArc(graph, edge.getOppositeNode(node), edge, node, e, e.getOppositeNode(node), radius, layer));
                        smoothing.addSmoothedEdges(e, edge);
                    }                    
                }
            }

        }
    }
    return arcs;
};

var addAlternateRouteByArc = func( graph,  start,  e1,  mid,  e2,  end,  radius,  layer) {
    return addArcToAngleSimple(graph, start, e1, mid.getLocation(), e2, end, radius, 1, 0, layer);
};

# Caclulation of an circle embedded in an angle. Either inner arc (covering beta) shortening v1->v2 or outer arc (covering alpha) reconnecting v2->v1
var calcArcParameter = func(   start,  e1,  intersection,  e2,  end,  radius,  inner,  radiusisdistance) {
    #logging.debug("building arc from " ~ start.getName() ~ start.getLocation().toString() ~ " on " ~ e1.toString() ~ " by " ~ intersection.getLocation().toString() ~ " on " ~ e2.toString() ~ " to " ~ end.getName() ~ end.getLocation().toString());
    var v1 = e1.getEffectiveOutboundDirection(start);
    var v2 = e2.getEffectiveInboundDirection(end);
    var alpha = PI - getAngleBetween(v1, v2);
    var beta = PI - alpha;
    var distancefromintersection = 0;
    if (radiusisdistance) {
        distancefromintersection = radius;
        radius = math.tan(alpha / 2) * distancefromintersection;
    } else {
        distancefromintersection = radius * math.tan(beta / 2);
    }
    var kp = getCrossProduct(v1, v2);
    var upVector = Vector3.new(0, 0, 1);
    if (kp.z > 0) {
        upVector = Vector3.new(0, 0, -1);
        beta = -beta;
    }
    #logging.debug("v1="~v1.toString());
    #logging.debug("v2="~v2.toString());
    #logging.debug("distancefromintersection="~distancefromintersection);
                    
    var radiusvector = getCrossProduct(v1, upVector).normalize().multiply(radius);
    v2 = v2.multiply(distancefromintersection);

    #logging.debug("v1="~v1.toString());
    #logging.debug("v2="~v2.toString());
    var arcbeginloc = start.getLocation().add(v1);
    arcbeginloc = intersection.subtract(v1.multiply(distancefromintersection));
    var arccenter = arcbeginloc.add(radiusvector);
    return {arccenter:arccenter, radius:radius, distancefromintersection:distancefromintersection, arcbeginloc:arcbeginloc, beta:beta, v2:v2, inner:inner};
};
    
addArcToAngleSimple = func( graph,  start,  e1,  mid,  e2,  end,  radius,  inner,  radiusisdistance,  layer) {
    var para = calcArcParameter(start, e1, mid, e2, end, radius, inner, radiusisdistance);
    var e1len = e1.getLength();
    var e2len = e2.getLength();

    if (para.distancefromintersection > e1len + 0.0001) {
        # not possible to draw arc
        logging.warn("skipping arc because of d=" ~ para.distancefromintersection ~ ", e1len=" ~ e1len);
        return nil;
    }
    if (para.distancefromintersection > e2len + 0.0001) {
        # not possible to draw arc
        logging.warn("skipping arc because of d=" ~ para.distancefromintersection ~ ", e2len=" ~ e2len);
        return nil;
    }

    return addArcToAngle(graph, start, e1, mid, e2, end, para, layer);
};
        
# Return edge of arc
addArcToAngle = func( graph, start, e1, mid, e2, end, para, layer) {
    var mindistancefornewnode = 0.1;
    var e2len = e2.getLength();

    var arcbegin = nil;
    if (getDistanceXYZ(para.arcbeginloc, start.getLocation()) > mindistancefornewnode) {
        arcbegin = graph.addNode("smoothbegin", para.arcbeginloc);
        graph.connectNodes(start, arcbegin, "smoothbegin", layer);
    } else {
        arcbegin = start;
    }
    var arcend = nil;
    if (e2len - para.distancefromintersection > mindistancefornewnode) {
        arcend = graph.addNode("smoothend", mid.add(para.v2));
        graph.connectNodes(arcend, end, "smoothend", layer);
    } else {
        arcend = end;
    }

    var arc = nil;
    arc = graph.connectNodes(arcbegin, arcend, "smootharc", layer);
    if (para.inner) {
        arc.setArc(para.arccenter, para.radius, -para.beta);
    } else {
        arc.setArc(para.arccenter, para.radius, -PI2 - para.beta);
    }
    return arc;                
};

var createBranch = func( graph,  node,  edge,  branchlen,  angle,  layer) {
    var branchdir = edge.getEffectiveOutboundDirection(node).rotate(buildRotationZ(angle));
    return extend(graph,node,branchdir,branchlen,layer);
};

var extend = func( graph,  node,  dir ,  len,  layer) {
    dir = dir.multiply(len);
    var destination = graph.addNode("ex", node.getLocation().add(dir));
    var branch = graph.connectNodes(node, destination, "", layer);
    return branch;
}

# Create teardrop by extending edge at node by an arc back to the opposite node on edge including smoothing of the intersection point.
# For now leads to the opposite node of inbound.
# layerid is created internally.
var addTearDropTurn = func( graph,  node,  edge,  left,  smoothingradius,  layer, smoothnode) {    
    var approach = edge;
    var vertex = approach.getOppositeNode(node);
    var angle = ((left) ? 1 : -1) * 90 / (approach.getLength() / 5);
    var branch = createBranch(graph, vertex, approach, approach.getLength(), angle, layer);
    branch.setName("teardrop.branch");
    var teardrop = addArcToAngleSimple(graph, branch.getOppositeNode(vertex), branch, vertex.getLocation(), approach, node, approach.getLength(), 0, 1, layer);
    teardrop.setName("teardrop.smootharc");
    return buildTearDropTurn(edge, branch, teardrop);
};
    
# Create loop turn on a node for having a smooth transition from inbound to outbound. Needed when a smoothing arc doesn't exist or is
# not reachable.
# By extending edge at node by a ahort edge, an arc and an edge back to the same node.
var addTurnLoop = func( graph,  node,  incoming,   outcoming,  layer) {
    #logging.debug("addTurnLoop: node="~node.toString()~",incoming="~incoming.toString()~",outcoming="~outcoming.toString());        
    var len = 20;#arbitrayry
    var e1 = extend(graph,node,incoming.getEffectiveInboundDirection(node),len,layer);
    e1.setName("e1");
    var e2 = extend(graph,node,outcoming.getEffectiveInboundDirection(node),len,layer);
    e2.setName("e2");
    var turnloop = addArcToAngleSimple(graph, e1.getTo(), e1, node.getLocation(), e2,e2.getTo(), len, 0, 1, layer);
    if (turnloop == nil){
        logging.warn("failed to create turnloop ");
        return nil;
    }
    turnloop.setName("turnloop.smootharc");
    return buildTearDropTurn(e1, e2, turnloop);
};

# Return path from some graph position to some node by avoiding edges "voidedges".
# 
# layerid is created internally.
# <p>
# Return nil if no path is found.
# Several solutions:
# 1) Try node in direction of orientation of current edge. If first segment is a current edge, a teardrop return is added.
#
var createPathFromGraphPosition = func( graph,  from,  to,  graphWeightProvider,  smoothingradius,  layer, smoothpath,  minimumlen) {
    var nextnode = from.getNodeInDirectionOfOrientation();
    graphWeightProvider = DefaultGraphWeightProvider.new(graph, 0);
    var path = graph.findPath(nextnode, to, graphWeightProvider);
    if (path == nil) {
        return nil;
    }
    logging.debug("createPathFromGraphPosition: from " ~ from.toString() ~ ",nextnode=" ~ nextnode.toString() ~ ",path=" ~ path.toString());
    if (path.getSegmentCount() == 0) {
        logging.warn("no path found");
        return nil;
    }
    path = bypassShorties(graph, path, minimumlen, layer);
    
    var smoothedpath = GraphPath.new(path.start, layer);
    logging.debug("smoothing path " ~ path.toString());
    var startpos = 1;
            
    if (path.getSegmentCount() > 0) {
        var firstsegment = path.getSegment(0);
        if (firstsegment.edge == from.currentedge) {
            # need to turn back to my current edge. Add teardrop for turning at the end of the current edge. 
            logging.debug("creating teardrop turn. firstsegment=" ~ firstsegment.edge.toString() ~ ",from=" ~ from.currentedge.toString());
            var turn = addTearDropTurn(graph, nextnode, from.currentedge, 1, smoothingradius, layer, 0);
            
            smoothedpath.addSegment(GraphPathSegment.new(turn.arc, nextnode));
            smoothedpath.addSegment(GraphPathSegment.new(turn.branch, turn.arc.getOppositeNode(nextnode)));
        }else{
            # first segment is not my current one. Need to find a smooth path into first segment.
            # current solution is turnloop.
            var turnloop = addTurnLoop(graph, nextnode, from.currentedge, firstsegment.edge, layer);
            if (turnloop == nil) {
                return nil;
            }
            smoothedpath.addSegment(GraphPathSegment.new(turnloop.edge, nextnode));
            smoothedpath.addSegment(GraphPathSegment.new(turnloop.arc, turnloop.edge.getOppositeNode(nextnode)));
            smoothedpath.addSegment(GraphPathSegment.new(turnloop.branch, turnloop.branch.getOppositeNode(nextnode)));
            startpos = 0;
        }
    }
    for (var i = startpos; i < path.getSegmentCount(); i+=1) {
        var segment = path.getSegment(i);
        var lastsegment = smoothedpath.getLast();
        var lastposition = buildPositionAtNode(lastsegment.edge, lastsegment.enternode,1);
        var transition = createTransition(graph, lastposition, segment.edge, segment.getLeaveNode(), smoothingradius, layer);
        
        if (transition == nil) {
            # no smooth transition
            smoothedpath.addSegment(segment);
        } else {            
            smoothedpath.replaceLast(transition);
        }

    }
    return smoothedpath;       
};

# bypass too short edges.
var bypassShorties = func( graph,  path,  minimumlen,  layer) {
    var np = GraphPath.new(path.start, path.layer);
    var lastsegment = nil;
    for (var i = 0; i < path.getSegmentCount(); i+=1) {
        var segment = path.getSegment(i);
        if (segment.edge.getLength() < minimumlen and i < path.getSegmentCount() - 1) {
            if (i == 0) {
                # bypass ahead
                var nextsegment = path.getSegment(i + 1);
                if (validateObject(lastsegment,"lastsegment","GraphPathSegment")) {
                    logging.error("validate of lastsegment failed");
                    return np;
                }
                if (validateObject(nextsegment,"nextsegment","GraphPathSegment")) {
                    logging.error("validate of nextsegment failed");
                    return np;
                }
                var bypass = graph.connectNodes(lastsegment.getLeaveNode(), nextsegment.getLeaveNode(), "bypass", layer);
                lastsegment = GraphPathSegment.new(bypass, lastsegment.getLeaveNode());
                np.addSegment(lastsegment);
                i+=1;
            } else {
                # bypass back
                var bypass = graph.connectNodes(lastsegment.enternode, segment.getLeaveNode(), "bypass", layer);
                lastsegment = GraphPathSegment.new(bypass, lastsegment.enternode);
                np.replaceLast(GraphTransition.new(lastsegment));
            }
        } else {                        
            np.addSegment(segment);
            lastsegment = segment;
        }
    }
    return np;
};

# intersecton of 2 edges. 2D only!
# returns locationXYZ
getIntersection = func( e1,  e2) {
    var line1start = buildXY(e1.getFrom().getLocation().getX(), e1.getFrom().getLocation().getY());
    var line1end = buildXY(e1.getTo().getLocation().getX(), e1.getTo().getLocation().getY());
    var line2start = buildXY(e2.getFrom().getLocation().getX(), e2.getFrom().getLocation().getY());
    var line2end = buildXY(e2.getTo().getLocation().getX(), e2.getTo().getLocation().getY());
    var intersection = getLineIntersection(line1start, line1end, line2start, line2end);
    if (intersection == nil) {
        return nil;
    }
    return Vector3.new(intersection.x, intersection.y, 0);
};

# create a smooth transition from edge fromedge to the other (which might be identical to "from") by adding one or two arcs and maybe some helper edges.
# Variants:
# a) add branch on current edge if the current position provides enough space.
# b) if a isn't possible, extend the current edge at the next node and add a turn loop.
# only 2D, z=0.
createTransition = func( graph,  from,  destinationedge,  destinationnode,  smoothingradius,  layer) {
    if (from.currentedge.getCenter() != nil) {
        logging.warn("not yet from arcs");
        return nil;
    }
    var nextnode = from.getNodeInDirectionOfOrientation();
    #logging.debug("createTransition from position " ~ from.toString() ~ " heading " ~ nextnode.toString() ~ " to " ~ destinationnode.toString() ~ " on " ~ destinationedge.toString());
   
    if (from.currentedge == destinationedge) {
        # need to turn back to my current edge. Add teardrop for turning at the end of the current edge. 
        var turn = addTearDropTurn(graph, nextnode, from.currentedge, 1, smoothingradius, layer, 0);
        var gt = GraphTransition.new();
        gt.add(GraphPathSegment.new(turn.arc, nextnode));
        gt.add(GraphPathSegment.new(turn.branch, turn.arc.getOppositeNode(nextnode)));
        return gt;
    }
    var destinationisconnected = 0;
    if (nextnode == destinationedge.getOppositeNode(destinationnode)) {
        destinationisconnected = 1;
    }
    # intersection cannot be used for checking parallel
    var isparallel = 0;
    var angle = getAngleBetween(from.currentedge.getDirection(), destinationedge.getDirection());
    if (angle < 0.0001 or angle > PI - 0.0001) {
        isparallel = 1;
    }
    if (isparallel) {
        # parallel destination edge. Depending on ahead od behind: s-turn; if edge disnace > ?? simple turnloop otherwise teardrop
        if (nextnode == destinationnode or destinationisconnected) {
            return nil;
        }

        #TODO not yet completed
        var turn = addTearDropTurn(graph, nextnode, from.currentedge, 1, smoothingradius, layer, 0);
        var gt = GraphTransition.new();
        gt.add(GraphPathSegment.new(turn.arc, nextnode));
        gt.add(GraphPathSegment.new(turn.branch, turn.arc.getOppositeNode(nextnode)));
        return gt;
    }
    var intersection = nil;
    if (destinationisconnected) {
        # easy way
        intersection = nextnode.getLocation();
    } else {
        intersection = getIntersection(from.currentedge, destinationedge);

        if (intersection == nil) {
            logging.warn("no intersection");
            return nil;
        }
    }
   
    var start = from.currentedge.getOppositeNode(nextnode);
    var e1 = from.currentedge;
    var arcpara = calcArcParameter(start, e1, intersection, destinationedge, destinationnode, smoothingradius, 1, 0);
    if (arcpara == nil) {
        return nil;
    }
    var relpos = compareEdgePosition(from, arcpara.arcbeginloc);
    #logging.debug("relpos=" ~ relpos);
    if (relpos > 0) {
        # arc ahead of current position. inner arc can be used.
        var arc = addArcToAngle(graph, start, e1, intersection, destinationedge, destinationnode, arcpara, layer);
        var gt = GraphTransition.new();
        #TODO oder arc.to? oder from?
        gt.add(GraphPathSegment.new(graph.connectNodes(start, arc.from, "smoothbegin." ~ nextnode.getName(),layer), start));
        gt.add(GraphPathSegment.new(arc, destinationedge.getOppositeNode(destinationnode)));
        gt.add(GraphPathSegment.new(graph.connectNodes(arc.to, destinationnode, "smoothend." ~ nextnode.getName(),layer), arc.getTo()));
        #logging.debug("created inner arc");
        return gt;
    } else if (relpos < 0) {
        #behind. Turnloop transition at the end of current edge.
        var len = 5;
        #??arcpara = calcArcParameter( start, e1, intersection, destinationedge, destinationnode, len, 0, 1);
        #??return createTurnLoop(graph,nextnode,e1,intersection,destinationedge,destinationnode,arcpara,layer);
        var turnloop = addTurnLoop(graph, nextnode, from.currentedge, destinationedge, layer);
        if (turnloop == nil) {
            return nil;
        }
        var gt = GraphTransition.new();
        gt.add(GraphPathSegment.new(turnloop.edge, nextnode));
        gt.add(GraphPathSegment.new(turnloop.arc, turnloop.edge.getOppositeNode(nextnode)));
        gt.add(GraphPathSegment.new(turnloop.branch, turnloop.edge.getOppositeNode(nextnode)));
        logging.debug("created turnloop");
        return gt;
    }

    logging.debug("created no transition");
    return nil;
};

# is "v" logically ahead (>0), on (0), or behind (<0) the current position?
# v must be on the same line as the edge!
compareEdgePosition = func( position,  v) {
    if (position.currentedge.getCenter() != nil) {
        logging.warn("not yet from arcs");
        return 0;
    }
    var locationXYZ = position.get3DPosition();
    var diffXYZ = v.subtract(locationXYZ);
    var difflen = diffXYZ.length();
    # value fitting for groundnet only?
    if (difflen < 0.01) {
        return 0;
    }
    var angle = getAngleBetween(position.currentedge.getEffectiveInboundDirection(position.getNodeInDirectionOfOrientation()), diffXYZ);
    if (angle < PI_2) {
        return difflen;
    }
    return -difflen;
};

logging.debug("completed GraphUtils.nas");