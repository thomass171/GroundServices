#
# 
#

logging.debug("executing maintest.nas");

var assertEquals = func (label,expected,actual) {
	if (expected != actual){
	    logging.error(label ~ ": expected "~expected~", actual "~actual);
	    return 1;
	}	
	return 0;
}

var assertFloat = func (label,expected,actual,epsilon=0.000003) {
	if (!isEqual(expected,actual,epsilon)) {
	    logging.error(label ~ ": expected "~expected~", actual "~actual);
	}	
}

var assertVector3 = func (label,expected,actual,epsilon=0.000003) {
	assertFloat(label~".x",expected.x,actual.x,epsilon);
    assertFloat(label~".y",expected.y,actual.y,epsilon);
    assertFloat(label~".z",expected.z,actual.z,epsilon);
}

var assertNotNull = func (label,obj) {
	if (obj == nil) {
	    logging.error(label ~ ": is nil");
	    
	}	
};

var assertTrue = func (label, obj) {
	if (!obj) {
	    logging.error(label ~ ": is false");	    
	}	
};

var assertPosition = func (expected, actual) {
    assertNotNull("position", actual);
    assertEquals("position.edge", expected.currentedge.getName(), actual.currentedge.getName());
    assertEquals("position.position", expected.edgeposition, actual.edgeposition);
    assertTrue("position.reverse", expected.isReverse()==actual.isReverse());
}

var assertA20position = func(a20position) {
    assertNotNull("a20position", a20position);
    assertEquals("a20position.edge", "1-201", a20position.currentedge.getName());
    assertEquals("a20position.position", 50.180775, a20position.edgeposition);
    assertTrue("a20position.reverse", a20position.isReverse());     
};

#
# large epsilon due to rounding effects
var groundnetEDDKTest = func() {
    logging.debug("running groundnetEDDKTest");
    var projection = Projection.new(geo.Coord.new().set_latlon(50.86538,7.139103));   
    var data = loadGroundnet(getprop("/sim/fg-root") ~ "/Nasal/groundservices/test/EDDK-refgroundnet.xml");

    var groundnet = Groundnet.new(projection, data.getChild("groundnet"), "A20");
    assertVector3("node0",Vector3.new(-1889.7698,-295.14346,0),groundnet.groundnetgraph.getNode(0).getLocation(),0.5);            
    assertEquals("nodes",241,groundnet.groundnetgraph.getNodeCount());
    if (assertEquals("edges",269,groundnet.groundnetgraph.getEdgeCount())) {
        #useless. groundet doesn't fit
        #return;
    }
    
    var parkpos_c_7 = groundnet.getParkPos("C_7");
    logging.debug("parkpos C_7:"~parkpos_c_7.name~",location.x=" ~ parkpos_c_7.node.getLocation().x);
    var c7loc = parkpos_c_7.node.getLocation();
    assertVector3("C_7location", Vector3.new(-1642, 1434, 0), Vector3.new(math.round(c7loc.getX()),math.round(c7loc.getY()),0));
     
    var gr = groundnet.groundnetgraph;
    var path = gr.findPath(gr.findNodeByName("16"), gr.findNodeByName("2"), nil);
    assertNotNull("findpath",path);
    
    var n134 = gr.findNodeByName("134");
    var c_7 = groundnet.getParkPos("C_7");
    path = gr.findPath(n134, groundnet.getParkPos("C_7").node, nil);
    assertEquals("path", "134:133-134->103-133(88)->207-103(24)->7-207(50)", path.toString());
    
    var startposition = buildPositionAtNode(gr.findEdgeByName("133-134"), n134,1);    
    path = createPathFromGraphPosition(gr,startposition , c_7.node, nil, SMOOTHINGRADIUS, 233, 0, MINIMUMPATHSEGMENTLEN);
    assertEquals("path to C_7", "133:e1->turnloop.smootharc(131)->e2(20)->smoothbegin.103(87)->smootharc(2)->smoothbegin.207(21)->smootharc(3)->smoothend.207(48)", path.toString());
    assertEquals("statistics","nodes:0:269;233:13;",gr.getStatistic());
    var gmc = GraphMovingComponent.new(nil,nil,startposition);
    gmc.setPath(path);
    gmc.moveForward(100000);
    var edge7_207 = gr.findEdgeByName("7-207");
    assertPosition(GraphPosition.new(edge7_207,edge7_207.getLength(),1),gmc.currentposition);
    gr.removeLayer(path.layer);
    assertEquals("edges",269,gr.getEdgeCount());
   
    # A20 to C_4
    var c_4 = groundnet.getParkPos("C_4").node;
    var a20 = groundnet.getVehicleHome();
    var a20position = groundnet.getParkingPosition(a20);
    a20position = GraphPosition.new(gr.findEdgeByName("1-201"),50.180775,1);
    assertA20position(a20position);
    path = groundnet.createPathFromGraphPosition(a20position, c_4);
    assertEquals("path to C_4", "1:e1->turnloop.smootharc(7)->e2(20)->smoothbegin.63(28)->smootharc(0)->smoothbegin.69(52)->smootharc(12)->smoothbegin.68(14)->smootharc(0)->smoothbegin.129(83)->smootharc(14)->smoothbegin.130(160)->smootharc(0)->smoothbegin.131(27)->smootharc(0)->smoothbegin.132(107)->smootharc(0)->smoothbegin.134(62)->smootharc(0)->smoothbegin.125(81)->smootharc(19)->smoothbegin.206(102)->smootharc(2)->smoothend.206(49)", path.toString());
    assertEquals("statistics","nodes:0:269;1:56;",gr.getStatistic());
    gmc = GraphMovingComponent.new(nil,nil,a20position);
    gmc.setPath(path);
    gmc.moveForward(100000);
    var edge6_206 = gr.findEdgeByName("6-206");
    assertPosition(GraphPosition.new(edge6_206,edge6_206.getLength(),1),gmc.currentposition);
    gr.removeLayer(path.layer);
    assertEquals("edges",269,gr.getEdgeCount());

    # Leaving C_4. (issue 2)
    var c_4position = groundnet.getParkingPosition(groundnet.getParkPos("C_4"));
    var e20 = groundnet.groundnetgraph.findNodeByName("16");
    path = groundnet.createPathFromGraphPosition(c_4position, e20);
    assertEquals("path from C_4", "6:e1->turnloop.smootharc(4)->e2(20)->smoothbegin.104(56)->smootharc(0)->smoothbegin.124(97)->smootharc(18)->smoothbegin.134(67)->smootharc(18)->smoothbegin.89(80)->smootharc(4)->smoothbegin.90(322)->smootharc(20)->smoothbegin.46(78)->smootharc(0)->smoothend.46(21)", path.toString());
    assertFloat("arccenter distance to 125", 17.89897, getDistanceXYZ(path.getSegment(6).edge.getCenter(), groundnet.groundnetgraph.findNodeByName("125").getLocation()),0.1);
    gmc = GraphMovingComponent.new(nil, nil, c_4position);
    gmc.setPath(path);
    gmc.moveForward(100000);
    gr.removeLayer(path.layer);
    assertEquals("edges", 269, gr.getEdgeCount());
        
    logging.debug("finished groundnetEDDKTest");
             
};

var groundnetOtherTest = func() {
    logging.debug("running groundnetOtherTest");
    var projection = Projection.new(geo.Coord.new().set_latlon(50.86538,7.139103));
    var path = getprop("/sim/fg-home") ~ "/TerraSync/Airports/E/H/A/EHAM.groundnet.xml";        
    var data = loadGroundnet(path); 
    if (data == nil) {
        logging.error("no groundnet for EHAM");
        return;    
    }             
    groundnet = Groundnet.new(projection, data.getChild("groundnet"), "");    
    logging.debug("finished groundnetOtherTest");
};

var miscTest = func() {
    logging.debug("running miscTest");
    var deg = parseDegree("N50 52.697864");
    assertFloat("C_7 lat",50.878298,deg);        
    deg = parseDegree("E7 7.458788");
    assertFloat("C_7 lon",7.124313,deg);
    logging.debug("finished miscTest");
};

var maintest = func {
	logging.debug("running maintest");
	
	miscTest();
    groundnetEDDKTest();
    groundnetOtherTest();
    logging.debug("maintest completed");
};

# from props.dump

var dump = func {
    if(size(arg) == 1) { prefix = "";     node = arg[0]; }
    else               { prefix = arg[0]; node = arg[1]; }

    index = node.getIndex();
    type = node.getType();
    name = node.getName();
    val = node.getValue();

    if(val == nil) { val = "nil"; }
    name = prefix ~ name;
    if(index > 0) { name = name ~ "[" ~ index ~ "]"; }
    logging.debug(name~ " {"~ type ~ "} = "~ val);

    # Don't recurse into aliases, lest we get stuck in a loop
    if(type != "ALIAS") {
        children = node.getChildren();
        foreach(var c; children) { dump(name ~ "/", c); }
    }
};


logging.debug("completed maintest.nas");