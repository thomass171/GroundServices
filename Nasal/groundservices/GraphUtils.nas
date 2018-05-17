#
#
#

logging.debug("executing GraphUtils.nas");

var graphutilsdebuglog = 0;

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
                var angle = Vector3.getAngleBetween(effectiveincomingdir, effectivedir);
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
    return addArcToAngleSimple(graph, start, e1, mid.getLocation(), e2, end, radius, 1, 0, layer, false);
};

var extendWithEdge = func(graph, edge, len, layer) {
    var toloc = edge.to.getLocation();
    var dir = edge.getDirection();
    var destination = toloc.add(dir.normalize().multiply(len));
    var destnode = graph.addNode("", destination);
    fixAltitude(destnode);        
    var e = graph.connectNodes(edge.to, destnode, "", layer);
    return e;
};

# Caclulation of an circle embedded in an angle. Either inner arc (covering beta) shortening v1->v2 or outer arc (covering alpha) reconnecting v2->v1
var calcArcParameter = func(   start,  e1,  intersection,  e2,  end,  radius,  inner,  radiusisdistance) {
    if (graphutilsdebuglog) {
        logging.debug("calc arc from " ~ start.getName() ~ start.getLocation().toString() ~ " by " ~ intersection.toString() ~ " to " ~ end.getName() ~ end.getLocation().toString());
    }
    if (validateAltitude(intersection.z)){
        #the reason is still unknown TODO
        logging.warn("fixing out of range altitude in intersection");
        intersection.z = (start.getLocation().z + end.getLocation().z)/2;
    }
    var v1 = e1.getEffectiveOutboundDirection(start);
    var v2 = e2.getEffectiveInboundDirection(end);
    var alpha = PI - Vector3.getAngleBetween(v1, v2);
    var beta = PI - alpha;
    var distancefromintersection = 0;
    if (radiusisdistance) {
        distancefromintersection = radius;
        radius = math.tan(alpha / 2) * distancefromintersection;
    } else {
        distancefromintersection = radius * math.tan(beta / 2);
    }
    var kp = Vector3.getCrossProduct(v1, v2);
    var upVector = Vector3.new(0, 0, 1);
    if (graphutilsdebuglog) {
        logging.debug("v1="~v1.toString());
        logging.debug("v2="~v2.toString());
        logging.debug("distancefromintersection="~distancefromintersection ~ ",radius=" ~ radius ~ ",alpha=" ~ alpha ~ ",beta=" ~ beta);
    }            
    var radiusvector = nil;
    var ex = Vector3.getCrossProduct(v1, kp).normalize();
    var ey = Vector3.getCrossProduct(v2, kp).normalize();
    v2 = v2.multiply(distancefromintersection);

    var arcbeginloc = intersection.subtract(v1.multiply(distancefromintersection));
    radiusvector = ex.negate().multiply(radius);
    var arccenter = arcbeginloc.add(radiusvector);
    if (graphutilsdebuglog) {
       logger.debug("arccenter=" ~ arccenter.toString());
       logger.debug("ex=" ~ ex.toString());
       logger.debug("radiusvector=" ~ radiusvector.toString());
    }
    if (!inner) {
        beta = beta - PI2;
    }
    return {arccenter:arccenter, radius:radius, distancefromintersection:distancefromintersection, arcbeginloc:arcbeginloc, beta:beta, v2:v2, crossproduct:kp, 
        arc: GraphArc.new(arccenter, radius, ex, kp, beta)};
};

var calcArcParameterAtConnectedEdges = func(e1, e2, radius, inner, radiusisdistance) {
    var intersectionnode = e1.getNodeToEdge(e2);
    if (intersectionnode == nil) {
        logger.error("edges not connected");
        return nil;
    }
    var start = e1.getOppositeNode(intersectionnode);
    var intersection = intersectionnode.getLocation();
    var end = e2.getOppositeNode(intersectionnode);
    return calcArcParameter(start, e1, intersection, e2, end, radius, inner, radiusisdistance);
};
    
var addArcToAngleSimple = func( graph,  start,  e1,  mid,  e2,  end,  radius,  inner,  radiusisdistance,  layer, nonregular) {
    var para = calcArcParameter(start, e1, mid, e2, end, radius, inner, radiusisdistance);
    var e1len = e1.getLength();
    var e2len = e2.getLength();

    # more tolerance is required here
    if (para.distancefromintersection > e1len + 0.1) {
        # not possible to draw arc
        logging.warn("skipping arc because of d=" ~ para.distancefromintersection ~ ", e1len=" ~ e1len);
        return nil;
    }
    if (para.distancefromintersection > e2len + 0.1) {
        # not possible to draw arc
        logging.warn("skipping arc because of d=" ~ para.distancefromintersection ~ ", e2len=" ~ e2len);
        return nil;
    }

    return addArcToAngle(graph, start, e1, mid, e2, end, para, layer, nonregular);
};
        
# Return edge of arc
addArcToAngle = func( graph, start, e1, mid, e2, end, para, layer, nonregular) {
    if (graphutilsdebuglog) {
        logging.debug("building arc from " ~ start.getName() ~ start.getLocation().toString() ~ " by " ~ mid.toString() ~ " to " ~ end.getName() ~ end.getLocation().toString());
    }
    var mindistancefornewnode = 0.1;
    var e2len = e2.getLength();

    var arcbegin = nil;
    if (Vector3.getDistanceXYZ(para.arcbeginloc, start.getLocation()) > mindistancefornewnode) {
        arcbegin = graph.addNode("smootharcfrom", para.arcbeginloc);
        fixAltitude(arcbegin);
        graph.connectNodes(start, arcbegin, "smoothbegin", layer);
    } else {
        arcbegin = start;
        logger.warn("arc low distance to start");
    }
    var arcend = nil;
    if (e2len - para.distancefromintersection > mindistancefornewnode) {
        arcend = graph.addNode("smootharcto", mid.add(para.v2));
        fixAltitude(arcend);
        graph.connectNodes(arcend, end, "smoothend", layer);
    } else {
        logger.warn("arc low distance to end");
        if (nonregular) {
            arcend = end;
        } else {
            arcend = graph.addNode("smootharcto", end.getLocation());
            fixAltitude(arcend);                        
        }
    }

    var arc = nil;
    arc = graph.connectNodes(arcbegin, arcend, "smootharc", layer);
    arc.setArc(para.arc);
    return arc;                
};

var createBranch = func( graph,  node,  edge,  branchlen,  angle,  layer) {
    var branchdir = edge.getEffectiveOutboundDirection(node).rotate(Quaternion.buildRotationZ(angle));
    return extend(graph,node,branchdir,branchlen,layer);
};

var extend = func( graph,  node,  dir ,  len,  layer) {
    dir = dir.multiply(len);
    var destination = graph.addNode("ex", node.getLocation().add(dir));
    fixAltitude(destination);
    var branch = graph.connectNodes(node, destination, "e", layer);
    return branch;
}

var extend2 = func( graph, node, location, nodename, edgename, layer) {
    var destination = graph.addNode(nodename, location);
    fixAltitude(destination);        
    var branch = graph.connectNodes(node, destination, edgename, layer);
    return branch;
}
    
# Create teardrop by extending edge at node by an arc back to the opposite node on edge including smoothing of the intersection point.
# For now leads to the opposite node of inbound.
# layerid is created internally.
var addTearDropTurn = func( graph,  node,  edge,  left,  smoothingradius,  layer, smoothnode) {    
    if (graphutilsdebuglog) {
        logger.debug("creating teardrop turn");
    }
    var approach = edge;
    var vertex = approach.getOppositeNode(node);
    var angle = ((left) ? 1 : -1) * 90 / (approach.getLength() / 5);
    var branch = createBranch(graph, vertex, approach, approach.getLength(), angle, layer);
    branch.setName("teardrop.branch");
    var teardrop = addArcToAngleSimple(graph, branch.getOppositeNode(vertex), branch, vertex.getLocation(), approach, node, approach.getLength(), 0, 1, layer, true);
    if (teardrop == nil){
        logging.warn("failed to create teardrop ");
        teardrop = graph.connectNodes(node, branch.getOppositeNode(vertex));
    } else {
        teardrop.setName("teardrop.smootharc");
    }
    if (smoothnode) {
        smoothNode(graph, vertex, smoothingradius, layer);
    }
    #return buildTearDropTurn(edge, branch, teardrop);
    return TurnExtension.new(edge, branch, teardrop);
};

# Create uturn from nextnode.
addUTurn = func(graph, nextnode, fromedge, destnode, destination, distance, smoothingradius, layer) {
    if (graphutilsdebuglog) {
        logger.debug("creating U turn");
    }
    var r = smoothingradius;
    var d = distance;
    var normal = Vector3.new(0, 0, 1);
    var maindir = fromedge.getEffectiveInboundDirection(nextnode);
    var vn = Vector3.getCrossProduct(maindir, normal).normalize();
    var vo = vn.multiply(smoothingradius);
    var s = math.sqrt(3 * r * r - r * d - d * d / 4);
    var vs = maindir.multiply(s);
    var angle =  -math.atan(s / (r + (d / 2)));

    var arc0center = nextnode.getLocation().add(vo);
    var arc1center = nextnode.getLocation().add(vn.negate().multiply(d / 2)).add(vs);
    var arc2center = destnode.getLocation().add(vo.negate());

    var e = arc1center.subtract(arc0center).multiply(0.5);
    var n0 = arc0center.add(e);
    var e0 = extend2(graph, nextnode, n0, "n0", "uturn0", layer);
    e0.setArc(GraphArc.new(arc0center, r, vo.negate(), normal, angle));

    var ex2 = arc1center.subtract(arc2center).multiply(0.5);
    var n1 = arc2center.add(ex2);
    var e1 = extend2(graph, e0.getTo(), n1, "n1", "uturn1", layer);
    e1.setArc( GraphArc.new(arc1center, r, e.negate(), normal, PI2 - 2 * (PI_2 - math.abs(angle))));

    var e2 = graph.connectNodes(e1.getTo(), destnode, "uturn2", layer);
    e2.setArc(GraphArc.new(arc2center, r, ex2, normal, angle));

    return TurnExtension.new(e0, e2, e1);
}
      
# Create loop turn on a node for having a smooth transition from inbound to outbound. Needed when a smoothing arc doesn't exist or is
# not reachable.
# By extending edge at node by a ahort edge, an arc and an edge back to the same node.
var addTurnLoop = func( graph,  node,  incoming,   outcoming,  layer) {
    if (graphutilsdebuglog) {
        logging.debug("creating turn loop: node="~node.toString()~",incoming="~incoming.toString()~",outcoming="~outcoming.toString());
    }        
    var len = 20;#arbitrary
    var e1 = extend(graph,node,incoming.getEffectiveInboundDirection(node),len,layer);
    e1.setName("e1");
    var e2 = extend(graph,node,outcoming.getEffectiveInboundDirection(node),len,layer);
    e2.setName("e2");
    var turnloop = addArcToAngleSimple(graph, e1.getTo(), e1, node.getLocation(), e2,e2.getTo(), len, 0, 1, layer, true);
    if (turnloop == nil){
        logging.warn("failed to create turnloop ");
        turnloop = graph.connectNodes(e1.getTo(), e2.getTo());
    } else {
        turnloop.setName("turnloop.smootharc");
    }
    return buildTearDropTurn(e1, e2, turnloop);
};

#name is "create" instead of "find" because a temporary arc is added.
#Return TurnExtension
var createBack = func(graph, node, dooredge, successor, layer) {
    var ext = extend(graph, dooredge.getOppositeNode(node), successor.getEffectiveInboundDirection(dooredge.getOppositeNode(node)), dooredge.getLength(), layer);
    var arc = addArcToAngleSimple(graph, node, dooredge, dooredge.getOppositeNode(node).getLocation(), ext, ext.to, dooredge.getLength(), 1, 1, layer, true);
    if (arc == nil) {
        logging.warn("createBack failed. skipping");
        arc = graph.connectNodes(node, ext.to);
    }
    return TurnExtension.new(ext, nil, arc);
};

# Return path from some graph position to some node by avoiding edges "voidedges".
# 
# layerid is created internally.
# <p>
# Return nil if no path is found.
# Several solutions:
# 1) Try node in direction of orientation of current edge. If first segment is a current edge, a teardrop return is added.
#
var createPathFromGraphPosition = func( graph,  from,  to,  graphWeightProvider,  smoothingradius,  layer, smoothpath,  minimumlen, allowrelocation=0, lane=nil) {
    var nextnode = from.getNodeInDirectionOfOrientation();
    if (graphWeightProvider == nil) {
        graphWeightProvider = DefaultGraphWeightProvider.new(graph, 0);
    }
    var path = graph.findPath(nextnode, to, graphWeightProvider);
    if (path == nil) {
        #warning only
        logger.warn("no path found from " ~ from.toString() ~ " to " ~ to.toString());
        return nil;
    }
    logging.info("createPathFromGraphPosition: from " ~ from.toString() ~ ",nextnode=" ~ nextnode.toString() ~ ",path=" ~ path.toString());
    if (path.getSegmentCount() == 0) {
        logging.warn("no path found");
        return nil;
    }
    return createPathFromGraphPositionAndPath(graph, path, nextnode, from, to, smoothingradius, layer, smoothpath, minimumlen, allowrelocation, lane);
}

var createPathFromGraphPositionAndPath = func (graph, path, nextnode, from, to, smoothingradius, layer, smoothpath, minimumlen, allowrelocation, lane) {
    if (lane == nil and path.getStart() != nextnode) {
        logger.warn("start != nextnode");
    }
    path = bypassShorties(graph, path, minimumlen, layer);
    if (path.getSegmentCount() == 0) {
        logging.warn("bypassShorties returned empty path");
        return nil;
    }
    
    var useuturn = false;
    if (lane != nil) {
        if (from.currentedge.equals(path.getSegment(0).edge)){
            useuturn=true;
        }
        path = createOutlinePath(graph, path, lane, layer,useuturn);
    }
            
    var smoothedpath = GraphPath.new(layer);
    smoothedpath.finalposition = buildPositionAtNode(path.getLast().edge,to,0);
    if (graphutilsdebuglog) {
        logging.debug("smoothing path " ~ path.toString() ~ ",useuturn=" ~ useuturn ~ ",allowrelocation=" ~ allowrelocation);
    }
    var startpos = 1;
            
    if (path.getSegmentCount() > 0) {
        var firstsegment = path.getSegment(0);
        
        if (from != nil) {
            if (firstsegment.edge == from.currentedge) {
                # need to turn back to my current edge. Add teardrop for turning at the end of the current edge. 
                if (graphutilsdebuglog) {                           
                    logging.debug("creating teardrop turn. firstsegment=" ~ firstsegment.edge.toString() ~ ",from=" ~ from.currentedge.toString());
                }
                var turn = addTearDropTurn(graph, nextnode, from.currentedge, 1, smoothingradius, layer, 0);
                if (turn == nil) {
                    return nil;
                }
                smoothedpath.addSegment(GraphPathSegment.new(turn.arc, nextnode));
                smoothedpath.addSegment(GraphPathSegment.new(turn.branch, turn.arc.getOppositeNode(nextnode)));
            } else {
                # first segment is not my current one. Need to find a smooth path into first segment.
                # current solution is turnloop.
                # but only for small angles. otherwise there will be unrealistic turnloops
                if (lane != nil and useuturn) {
                    var uturn = addUTurn(graph, nextnode, from.currentedge, firstsegment.getEnterNode(), firstsegment.edge, lane.offset, smoothingradius, layer);
                    if (uturn == nil) {
                        return nil;
                    }
                    smoothedpath.addSegment( GraphPathSegment.new(uturn.edge, nextnode));
                    smoothedpath.addSegment( GraphPathSegment.new(uturn.arc, uturn.edge.getOppositeNode(nextnode)));
                    smoothedpath.addSegment( GraphPathSegment.new(uturn.branch, uturn.branch.getOppositeNode(firstsegment.getEnterNode())));
                    smoothedpath.addSegment(firstsegment);
                    startpos = 1;
                } else {
                    var relocationgt = nil;
                    if (allowrelocation) {
                        relocationgt = buildInnerArcOrTurnloopTransition(graph, from, nextnode, nextnode, nextnode.getLocation(), firstsegment.edge,
                                firstsegment.edge.getOppositeNode(nextnode), smoothingradius, layer);
                        if (graphutilsdebuglog) {                           
                            logger.debug("relocation gt=" ~ relocationgt.toString());
                        }
                    }
                    if (relocationgt != nil) {
                        smoothedpath.replaceLast(relocationgt);
                        smoothedpath.startposition = GraphPosition.new(relocationgt.seg[0].edge, from.edgeposition, false);
                        startpos = 1;
                    } else {                          
                        var angle = GraphEdge.getAngleBetweenEdges(from.currentedge, nextnode, firstsegment.edge);
                        if (graphutilsdebuglog) {                           
                            logger.debug("angle=" ~ angle);
                        }
                        if (angle < 0.05 or angle > 3.14) {
                            smoothedpath.addSegment(firstsegment);
                            startpos = 1;
                        } else {
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
                } 
            }
        } else {
            # No "from".
            smoothedpath.addSegment(path.getSegment(0));
            startpos = 1;
        }
    }
    for (var i = startpos; i < path.getSegmentCount(); i+=1) {
        var segment = path.getSegment(i);
        var lastsegment = smoothedpath.getLast();
        if (smoothpath) {
            var lastposition = buildPositionAtNode(lastsegment.edge, lastsegment.enternode,1);
            var transition = createTransition(graph, lastposition, segment.edge, segment.getLeaveNode(), smoothingradius, layer);
        
            if (transition == nil) {
                # no smooth transition
                smoothedpath.addSegment(segment);
            } else {            
                smoothedpath.replaceLast(transition);
            }
        } else {
            # no smoothing
            smoothedpath.addSegment(segment);
        }
    }
    if (graphutilsdebuglog) {
        logger.debug("smoothed path: " ~ ((smoothedpath==nil)?"nil":smoothedpath.toString()));
    }
    return smoothedpath;       
};

# bypass too short edges.
var bypassShorties = func( graph,  path,  minimumlen,  layer) {
    var np = GraphPath.new(path.layer);
    var lastsegment = nil;
    for (var i = 0; i < path.getSegmentCount(); i+=1) {
        var segment = path.getSegment(i);
        if (segment.edge.getLayer() == 0 and segment.edge.getLength() < minimumlen and i < path.getSegmentCount() - 1) {
            if (i == 0) {
                # bypass ahead
                if (graphutilsdebuglog) {
                #    logging.debug("bypass ahead. segment "~i);
                }
                var nextsegment = path.getSegment(i + 1);
                #if (validateObject(lastsegment,"lastsegment","GraphPathSegment")) {
                #    logging.error("validate of lastsegment failed");
                #    return np;
                #}
                #if (validateObject(nextsegment,"nextsegment","GraphPathSegment")) {
                #    logging.error("validate of nextsegment failed");
                #    return np;
                #}
                var bypass = graph.connectNodes(path.getSegment(0).enternode, nextsegment.getLeaveNode(), "bypass", layer);
                lastsegment = GraphPathSegment.new(bypass, path.getSegment(0).enternode);
                np.addSegment(lastsegment);
                i+=1;
            } else {
                # bypass back
                if (graphutilsdebuglog) {
                    #logging.debug("bypass back segment "~i);
                }
                var bypass = graph.connectNodes(lastsegment.enternode, segment.getLeaveNode(), "bypass", layer);
                lastsegment = GraphPathSegment.new(bypass, lastsegment.enternode);
                np.replaceLast(GraphTransition.new(lastsegment));
            }
        } else {   
            if (graphutilsdebuglog) {
                #logging.debug("no bypass segment "~i);
            }                     
            np.addSegment(segment);
            lastsegment = segment;
        }
    }
    return np;
};

# intersecton of 2 edges. 2D only!
# returns locationXYZ
var getIntersection = func( e1,  e2) {
    var line1start = Vector2.new(e1.getFrom().getLocation().getX(), e1.getFrom().getLocation().getY());
    var line1end = Vector2.new(e1.getTo().getLocation().getX(), e1.getTo().getLocation().getY());
    var line2start = Vector2.new(e2.getFrom().getLocation().getX(), e2.getFrom().getLocation().getY());
    var line2end = Vector2.new(e2.getTo().getLocation().getX(), e2.getTo().getLocation().getY());
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
var createTransition = func( graph,  from,  destinationedge,  destinationnode,  smoothingradius,  layer) {
    var connectingnode = nil;
    if (from.currentedge.getCenter() != nil) {
        logging.warn("not yet from arcs");
        return nil;
    }
    var nextnode = from.getNodeInDirectionOfOrientation();
    if (graphutilsdebuglog) {
        logging.debug("createTransition from position " ~ from.toString() ~ " heading " ~ nextnode.toString() ~ " to " ~ destinationnode.toString() ~ " on " ~ destinationedge.toString());
    }
    if (from.currentedge == destinationedge) {
        # need to turn back to my current edge. Add teardrop for turning at the end of the current edge. 
        var turn = addTearDropTurn(graph, nextnode, from.currentedge, 1, smoothingradius, layer, 0);
        if (turn == nil) {
            return nil;
        }
        var gt = GraphTransition.new();
        gt.add(GraphPathSegment.new(turn.arc, nextnode));
        gt.add(GraphPathSegment.new(turn.branch, turn.arc.getOppositeNode(nextnode)));
        return gt;
    }
    var destinationisconnected = 0;
    if (nextnode == destinationedge.getOppositeNode(destinationnode)) {
        destinationisconnected = 1;
        connectingnode = nextnode;
    }
    # intersection cannot be used for checking parallel
    var isparallel = 0;
    var angle = Vector3.getAngleBetween(from.currentedge.getDirection(), destinationedge.getDirection());
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
        if (turn == nil) {
            return nil;
        }
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
   
    var gt = buildInnerArcOrTurnloopTransition(graph, from, nextnode, connectingnode, intersection, destinationedge, destinationnode, smoothingradius, layer);
    if (gt != nil) {
        return gt;
    }       
    
    if (graphutilsdebuglog) {
        logging.warn("created no transition");
    }
    return nil;
};

# returns GraphTransition
var buildInnerArcOrTurnloopTransition = func(graph, from, nextnode,connectingnode , intersection, destinationedge, destinationnode, smoothingradius, layer) {
    var destinationisconnected = connectingnode != nil;
    var relpos = 0;
    for (var i = 0; i < 4; i+=1) {
        var start = from.currentedge.getOppositeNode(nextnode);
        var e1 = from.currentedge;
        var arcpara = nil;
        if (destinationisconnected) {
            arcpara = calcArcParameterAtConnectedEdges(e1, destinationedge, smoothingradius, true, false);
            if (arcpara == nil) {
                # already logged
                return nil;
            }
            arcpara.arc.origin=connectingnode;
        } else {
            arcpara = calcArcParameter(start, e1, intersection, destinationedge, destinationnode, smoothingradius, true, false);
            if (arcpara == nil) {
                #already logged
                return nil;
            }
        }
        relpos = compareEdgePosition(from, arcpara.arcbeginloc);
        if (graphutilsdebuglog) {
            logger.debug("relpos=" ~ relpos);
        }
        if (relpos > 0) {
            # arc ahead of current position. inner arc can be used.
            var arc = addArcToAngle(graph, start, e1, intersection, destinationedge, destinationnode, arcpara, layer, false);
            if (arc == nil) {
                logger.warn("createTransition: inner arc failed. Too large?");
                return nil;
            }
            var gt = GraphTransition.new();
            gt.add(GraphPathSegment.new(graph.connectNodes(start, arc.from, "smoothbegin." ~ nextnode.getName(), layer), start));
            gt.add(GraphPathSegment.new(arc, arc.from));
            gt.add(GraphPathSegment.new(graph.connectNodes(arc.to, destinationnode, "smoothend." ~ nextnode.getName(), layer), arc.getTo()));
            if (graphutilsdebuglog) {
                logger.debug("created inner arc");
            }
            return gt;
        }
        smoothingradius *= 0.8;
    }
    if (relpos < 0) {
        #behind. Turnloop transition at the end of current edge. Logging because this might be ugly?
        logger.warn("building turn loop transition");
        var len = 5;
        var turnloop = addTurnLoop(graph, nextnode, from.currentedge, destinationedge, layer);
        var gt = GraphTransition.new();
        gt.add(GraphPathSegment.new(turnloop.edge, nextnode));
        gt.add(GraphPathSegment.new(turnloop.arc, turnloop.edge.getOppositeNode(nextnode)));
        gt.add(GraphPathSegment.new(turnloop.branch, turnloop.edge.getOppositeNode(nextnode)));
        if (graphutilsdebuglog) {
            logger.debug("created turnloop");
        }
        return gt;
    }
    # no transition possible. Probably never reached here.
    return nil;
}
    
# is "v" logically ahead (>0), on (0), or behind (<0) the current position?
# v must be on the same line as the edge!
var compareEdgePosition = func( position,  v) {
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
    var angle = Vector3.getAngleBetween(position.currentedge.getEffectiveInboundDirection(position.getNodeInDirectionOfOrientation()), diffXYZ);
    if (angle < PI_2) {
        return difflen;
    }
    return -difflen;
};

var createBackPathFromGraphPosition = func(graph, turn, to, graphWeightProvider, smoothingradius, layer, smoothpath, minimumlen, allowrelocation, lane) {
    var path = createPathFromGraphPosition(graph, GraphPosition.new(turn.edge, turn.edge.getLength(), 1), to, graphWeightProvider, smoothingradius, layer, smoothpath, minimumlen, allowrelocation, lane);
    if (path == nil) {
        return nil;
    }
    # path is from successor. prepend turn edge
    var s = GraphPathSegment.new(turn.edge, turn.edge.to);
    s.changeorientation = 1;
    path.backward = 1;
    path.insertSegment(0, s);
    path.start = turn.edge.to;
    # from of arc is start node, but reverse and drive back
    path.startposition = GraphPosition.new(turn.arc, turn.arc.getLength(), 1);
    return path;
};

var createOutlinePath = func( graph, path, graphlane, layer, beginwithoutline) {
    var offset = graphlane.offset;

    var outline = graph.orientation.getOutline(path.path, offset, 0);
    var from = nil;
    if (beginwithoutline) {
        from = graph.addNode("outline0", outline[0]);
        fixAltitude(from);                    
    }else{
        from = path.getSegment(0).getEnterNode();
    }

    var e = nil;
    var newpath = GraphPath.new(layer);
    for (var i = 1; i < size(outline) - 2; i+=1) {
        var destnode = graph.addNode("outline" ~ i, outline[i]);
        fixAltitude(destnode);                    
        destnode.parent = path.getSegment(i).getEnterNode();
        e = graph.connectNodes(from, destnode, "toOutline" ~ i, layer);
        newpath.addSegment(GraphPathSegment.new(e, from));
        from = destnode;
    }
    var reenternode = path.getLast().getEnterNode();
    e = graph.connectNodes(from, reenternode, "reenter", layer);
    newpath.addSegment(GraphPathSegment.new(e, from));
    e = graph.connectNodes(reenternode, path.getLast().getLeaveNode(), "last", layer);
    newpath.addSegment(GraphPathSegment.new(e, reenternode));
    logger.debug("outline path created:" ~ newpath.toString());
    return newpath;
}
    
logging.debug("completed GraphUtils.nas");