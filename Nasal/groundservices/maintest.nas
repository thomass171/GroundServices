#
# 
#

logging.debug("executing maintest.nas");

var unittesting = 0;
var virtualtestingaltitude = 448;
#nonsens, so only for test.
var DEFAULTELEVATION=virtualtestingaltitude;

var TestUtil = {
    assertEquals : func (label,expected,actual) {
	    if (expected != actual){
	        logging.error(label ~ ": expected "~expected~", actual "~actual);
	        return 1;
	    }	
	    return 0;
    },
    assertFloat : func (label,expected,actual,epsilon=0.000003) {
	    if (!isEqual(expected,actual,epsilon)) {
	        logging.error(label ~ ": expected "~expected~", actual "~actual);
	    }
	},
    assertVector3 : func (label,expected,actual,epsilon=0.000003) {
	    TestUtil.assertFloat(label~".x",expected.x,actual.x,epsilon);
        TestUtil.assertFloat(label~".y",expected.y,actual.y,epsilon);
        TestUtil.assertFloat(label~".z",expected.z,actual.z,epsilon);
    },
    assertVector2 : func (label,expected,actual,epsilon=0.000003) {
	    TestUtil.assertFloat(label~".x",expected.x,actual.x,epsilon);
        TestUtil.assertFloat(label~".y",expected.y,actual.y,epsilon);    
    },
    assertNotNull : func (label,obj) {
	    if (obj == nil) {
	        logging.error(label ~ ": is nil");
	    }	    
	},	
    assertTrue : func (label, obj) {
	    if (!obj) {
	        logging.error(label ~ ": is false");	    
	    }
	},
	assertFalse : func (label, obj) {
        if (obj) {
            logging.error(label ~ ": is true");	    
        }
    },	
};

var assertPosition = func (expected, actual) {
    TestUtil.assertNotNull("position", actual);
    TestUtil.assertEquals("position.edge", expected.currentedge.getName(), actual.currentedge.getName());
    TestUtil.assertEquals("position.position", expected.edgeposition, actual.edgeposition);
    TestUtil.assertTrue("position.reverse", expected.isReverse()==actual.isReverse());
}

var assertA20position = func(a20position) {
    TestUtil.assertNotNull("a20position", a20position);
    TestUtil.assertEquals("a20position.edge", "1-201", a20position.currentedge.getName());
    TestUtil.assertEquals("a20position.position", 50.180775, a20position.edgeposition);
    TestUtil.assertTrue("a20position.reverse", a20position.isReverse());     
};

var loadGroundNetForTest = func(icao) {
    var projection = Projection.new(geo.Coord.new().set_latlon(50.86538,7.139103));   
    var data = loadGroundnet(root ~ "/Nasal/groundservices/test/"~icao~"-refgroundnet.xml");
    var groundnet = Groundnet.new(projection, data.getChild("groundnet"), "A20");
    return groundnet;
};

#
# large epsilon due to rounding effects
var groundnetEDDKTest = func() {
    logging.debug("running groundnetEDDKTest");
    var groundnet = loadGroundNetForTest("EDDK");
    TestUtil.assertVector3("node0",Vector3.new(-1889.7698,-295.14346,virtualtestingaltitude),groundnet.groundnetgraph.getNode(0).getLocation(),0.5);            
    TestUtil.assertEquals("nodes",241,groundnet.groundnetgraph.getNodeCount());
    if (TestUtil.assertEquals("edges",269,groundnet.groundnetgraph.getEdgeCount())) {
        #useless. groundet doesn't fit
        #return;
    }
    
    var parkpos_c_7 = groundnet.getParkPos("C_7");
    logging.debug("parkpos C_7:"~parkpos_c_7.name~",location.x=" ~ parkpos_c_7.node.getLocation().x);
    var c7loc = parkpos_c_7.node.getLocation();
    TestUtil.assertVector3("C_7location", Vector3.new(-1642, 1434, 0), Vector3.new(math.round(c7loc.getX()),math.round(c7loc.getY()),0));
     
    var gr = groundnet.groundnetgraph;
    var path = gr.findPath(gr.findNodeByName("16"), gr.findNodeByName("2"), nil);
    TestUtil.assertNotNull("findpath",path);
    
    var n134 = gr.findNodeByName("134");
    var c_7 = groundnet.getParkPos("C_7");
    path = gr.findPath(n134, groundnet.getParkPos("C_7").node, nil);
    TestUtil.assertEquals("path", "134:133-134->103-133(88)->207-103(24)->7-207(50)", path.toString());
    
    var startposition = buildPositionAtNode(gr.findEdgeByName("133-134"), n134,1);    
    path = createPathFromGraphPosition(gr,startposition , c_7.node, nil, SMOOTHINGRADIUS, 233, 1, MINIMUMPATHSEGMENTLEN);
    TestUtil.assertEquals("path to C_7", "133:e1->turnloop.smootharc(131)->e2(20)->smoothbegin.103(87)->smootharc(2)->smoothbegin.207(21)->smootharc(3)->smoothend.207(48)", path.toString());
    TestUtil.assertEquals("statistics","nodes:0:269;233:13;",gr.getStatistic());
    var gmc = GraphMovingComponent.new(nil,nil,startposition);
    gmc.setPath(path);
    gmc.moveForward(100000);
    var edge7_207 = gr.findEdgeByName("7-207");
    assertPosition(GraphPosition.new(edge7_207,edge7_207.getLength(),1),gmc.currentposition);
    gr.removeLayer(path.layer);
    TestUtil.assertEquals("edges",269,gr.getEdgeCount());
   
    # A20 to C_4
    var c_4 = groundnet.getParkPos("C_4").node;
    var a20 = groundnet.getVehicleHome();
    var a20position = groundnet.getParkingPosition(a20);
    a20position = GraphPosition.new(gr.findEdgeByName("1-201"),50.180775,1);
    assertA20position(a20position);
    path = groundnet.createPathFromGraphPosition(a20position, c_4);
    TestUtil.assertEquals("path to C_4", "1:e1->turnloop.smootharc(7)->e2(20)->smoothbegin.63(28)->smootharc(0)->smoothbegin.69(52)->smootharc(12)->smoothbegin.68(14)->smootharc(0)->smoothbegin.129(83)->smootharc(14)->smoothbegin.130(160)->smootharc(0)->smoothbegin.131(27)->smootharc(0)->smoothbegin.132(107)->smootharc(0)->smoothbegin.134(62)->smootharc(0)->smoothbegin.125(81)->smootharc(19)->smoothbegin.206(102)->smootharc(2)->smoothend.206(49)", path.toString());
    TestUtil.assertEquals("statistics","nodes:0:269;1:56;",gr.getStatistic());
    gmc = GraphMovingComponent.new(nil,nil,a20position);
    gmc.setPath(path);
    gmc.moveForward(100000);
    var edge6_206 = gr.findEdgeByName("6-206");
    assertPosition(GraphPosition.new(edge6_206,edge6_206.getLength(),1),gmc.currentposition);
    gr.removeLayer(path.layer);
    TestUtil.assertEquals("edges",269,gr.getEdgeCount());

    # Leaving C_4. (issue 2)
    var c_4position = groundnet.getParkingPosition(groundnet.getParkPos("C_4"));
    var e20 = groundnet.groundnetgraph.findNodeByName("16");
    path = groundnet.createPathFromGraphPosition(c_4position, e20);
    TestUtil.assertEquals("path from C_4", "6:e1->turnloop.smootharc(4)->e2(20)->smoothbegin.104(56)->smootharc(0)->smoothbegin.124(97)->smootharc(18)->smoothbegin.134(67)->smootharc(18)->smoothbegin.89(80)->smootharc(4)->smoothbegin.90(322)->smootharc(20)->smoothbegin.46(78)->smootharc(0)->smoothend.46(21)", path.toString());
    var center = path.getSegment(6).edge.getCenter();
    TestUtil.assertNotNull("center",center);            
    TestUtil.assertFloat("arccenter distance to 125", 17.89897, Vector3.getDistanceXYZ(center, groundnet.groundnetgraph.findNodeByName("125").getLocation()),0.1);
    gmc = GraphMovingComponent.new(nil, nil, c_4position);
    gmc.setPath(path);
    gmc.moveForward(100000);
    gr.removeLayer(path.layer);
    TestUtil.assertEquals("edges", 269, gr.getEdgeCount());
        
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
    TestUtil.assertFloat("C_7 lat",50.878298,deg);        
    deg = parseDegree("E7 7.458788");
    TestUtil.assertFloat("C_7 lon",7.124313,deg);
    deg = parseDegree("W00 27.303");
    TestUtil.assertFloat("W",-0.45505,deg);
    var ils14l = geo.Coord.new().set_latlon(50.852867,7.169064);
    ils14l.apply_course_distance(137.58+180, 2500);
    logging.debug("ils14l(course)="~ils14l.lat() ~ "," ~ ils14l.lon());
    logging.debug("finished miscTest");
};

var testServicePoint747_B2 = func() {
    logging.debug("running testServicePoint747_B2");
    var groundnet = loadGroundNetForTest("EDDK");
        
    var b_2 = groundnet.getParkPos("B_2");
    var sp = ServicePoint.new(groundnet, {type:"747-400", coord:geo.Coord.new()}, b_2.node.getLocation(), b_2.heading, getAircraftConfiguration("747-400"));
    TestUtil.assertVector3("prjdoorpos",Vector3.new(-1698.4425,1320.0948,virtualtestingaltitude),sp.prjdoorpos,0.1);
    TestUtil.assertEquals("wingreturnlayer",4,sp.wingreturn.getLayer());
    
    var wingapproachlen = sp.wingapproach.getLength();
    TestUtil.assertFloat("wingapproachlen", 30, wingapproachlen);
    # fuel truck approach. 
    var start = GraphPosition.new(groundnet.groundnetgraph.findEdgeByName("129-130"));
    # first without smoothing.
    var path = sp.getApproach(start, sp.wingedge.to, 0);
    TestUtil.assertEquals("path", "130:e1->turnloop.smootharc(69)->e2(20)->100-130(88)->202-100(27)->branchedge(18)->wingapproach(30)->wingedge(20)", path.toString());
    groundnet.groundnetgraph.removeLayer(path.layer);
    
    # back path
    path = sp.getWingReturnPath(0);
    TestUtil.assertEquals("path", "outernode:return0->return1(20)->return12(19)->bypass(45)->65-64(53)->64-68(39)->68-69(21)->63-69(59)->1-63(28)", path.toString());
    groundnet.groundnetgraph.removeLayer(path.layer);
    # now with smoothing
    path = sp.getWingReturnPath(1);
    TestUtil.assertEquals("path", "outernode:smoothbegin.->smootharc(12)->smoothbegin.ex(8)->smootharc(10)->smoothbegin.3(1)->smootharc(18)->smoothbegin.65(33)->smootharc(0)->smoothbegin.64(49)->smootharc(9)->smoothbegin.68(10)->smootharc(24)->smoothend.68(0)->smoothbegin.63(59)->smootharc(0)->smoothend.63(28)", path.toString());
    groundnet.groundnetgraph.removeLayer(path.layer);
    
    # now from A20. Catering must not move beneath aircraft
    var edge1_201 = groundnet.groundnetgraph.findEdgeByName("1-201");            
    start = GraphPosition.new(edge1_201);
    path = sp.getApproach(start, sp.doorEdge.from, 0);
    TestUtil.assertEquals("path", "201:e1->turnloop.smootharc(9)->e2(20)->201-63(23)->63-69(59)->68-69(21)->129-68(91)->129-130(169)->130-131(27)->101-131(100)->branchedge(16)->wingedge(16)->door2wing(26)->dooredge(16)", path.toString());
    groundnet.groundnetgraph.removeLayer(path.layer);
    path = sp.getApproach(start, sp.wingedge.to, 0);
    groundnet.groundnetgraph.removeLayer(path.layer);
    
    var schedule = Schedule.new(sp, groundnet);
    schedule.addAction(VehicleOrderAction.new(schedule, VEHICLE_CATERING, sp.doorEdge.from));
    schedule.addAction(VehicleServiceAction.new(schedule,2));
    schedule.addAction(VehicleReturnAction.new(schedule, 1,sp,1));
    schedule = Schedule.new(sp, groundnet);
    schedule.addAction(VehicleOrderAction.new(schedule, VEHICLE_FUELTRUCK, sp.wingedge.to));
    schedule.addAction(VehicleServiceAction.new(schedule,2));
    schedule.addAction(VehicleReturnAction.new(schedule, 0,sp,0));
    
    testUturnA20ServicePoint747_B2(groundnet, sp);
    # groundnet ist multilane now. Path back from door.
    path = sp.getDoorReturnPath(false);
    # rounding problem toOutline1(25)/toOutline1(26)?
    TestUtil.assertEquals("path", "[back on smootharc]ex:e->toOutline1(26)->toOutline2(16)->toOutline3(16)->toOutline4(95)->toOutline5(22)->toOutline6(164)->toOutline7(87)->toOutline8(25)->reenter(63)->last(28)", path.toString());
    groundnet.groundnetgraph.removeLayer(path.layer);
    # per multilane from A20 (1-201) to door. turnloop must fit to outline 
    start = GraphPosition.new(edge1_201,edge1_201.getLength(),true);
    path = sp.getApproach(start, sp.doorEdge.from, false);
    # rounding problem reenter(25)/reenter(26)?
    TestUtil.assertEquals("path", "1:e1->turnloop.smootharc(17)->e2(20)->toOutline1(29)->toOutline2(55)->toOutline3(17)->toOutline4(96)->toOutline5(173)->toOutline6(33)->toOutline7(106)->toOutline8(16)->toOutline9(16)->reenter(26)->last(16)", path.toString());
    TestUtil.assertEquals("path", "1:e1--ex-->turnloop.smootharc(17)--ex-->e2(20)--1-->toOutline1(29)--outline1@63-->toOutline2(55)--outline2@69-->toOutline3(17)--outline3@68-->toOutline4(96)--outline4@129-->toOutline5(173)--outline5@130-->toOutline6(33)--outline6@131-->toOutline7(106)--outline7@101-->toOutline8(16)--outline8@wing1-->toOutline9(16)--outline9@wing0-->reenter(26)--door1-->last(16)", path.getDetailedString());
    groundnet.groundnetgraph.removeLayer(path.layer);
    
    sp.delete();
    TestUtil.assertEquals("edges", 269, groundnet.groundnetgraph.getEdgeCount());
    
    logging.debug("finished testServicePoint747_B2");
}

#
# subtest from above
# Per multilane/outline from A20 (1-63, not 1-201, for fitting U-Turn) to door. Must begin with UTurn. First without, then with smoothing.
#
var testUturnA20ServicePoint747_B2 = func(groundnet, sp) {
    groundnet.multilaneenabled = true;
    var edge1_63 = groundnet.groundnetgraph.findEdgeByName("1-63");
    var start =  GraphPosition.new(edge1_63, edge1_63.getLength(), true);
    var path = sp.getApproach(start, sp.doorEdge.from, false);
    var node131 = groundnet.groundnetgraph.findNodeByName("131");
    logger.debug("path="~path.toString());
    var segToOutline2at69 = path.getSegment(4);
    # values plausible at 69
    TestUtil.assertVector3("outline at 69", Vector3.new(-1748,1116,virtualtestingaltitude),segToOutline2at69.getLeaveNode().getLocation(),1);
    var segToOutlineat129 = path.getSegment(6);
    # values plausible at 129.
    TestUtil.assertVector3("outline at 129", Vector3.new(-1640,1083,virtualtestingaltitude),segToOutlineat129.getLeaveNode().getLocation(),1);
    var segToOutlineat131 = path.getSegment(8);
    # values plausible at 131
    TestUtil.assertVector3("outline at 131", Vector3.new(-1547,1266,virtualtestingaltitude),segToOutlineat131.getLeaveNode().getLocation(),1);
    groundnet.groundnetgraph.removeLayer(path.layer);

    path = sp.getApproach(start, sp.doorEdge.from, true);
    
    # turnloop is indicator for failed bypassshorties
    TestUtil.assertFalse("turnloop in path", contains(path.toString(),"turnloop"));
    for (i = 0; i < path.getSegmentCount(); i=i+1) {
        var seg = path.getSegment(i);
        TestUtil.assertFloat("outline.z", DEFAULTELEVATION, seg.getEnterNode().getLocation().getZ());
    }
    # despite outline the end must be at the door. Must be tested at edge because vehicle stops before doorpos.
    TestUtil.assertVector3("outline.end",sp.doorEdge.getFrom().getLocation(),path.getSegment(path.getSegmentCount()-1).getLeaveNode().getLocation());
    groundnet.groundnetgraph.removeLayer(path.layer);
}

var testServicePoint737_C4 = func() {
    logging.debug("running testServicePoint737_C4");
    var groundnet = loadGroundNetForTest("EDDK");
        
    var c_4 = groundnet.getParkPos("C_4");
    var sp = ServicePoint.new(groundnet, {type:"738", coord:geo.Coord.new()}, c_4.node.getLocation(), c_4.heading, getAircraftConfiguration("738"));
    TestUtil.assertVector3("prjdoorpos",Vector3.new(-1605.639057507902,1535.3408,virtualtestingaltitude),sp.prjdoorpos,0.1);
    TestUtil.assertVector2("prjleftwingapproachpoint",Vector2.new(-1592.258,1519.9026),sp.prjleftwingapproachpoint,0.1);
    TestUtil.assertEquals("wingreturnlayer",4,sp.wingreturn.getLayer());
    TestUtil.assertVector3("wingedge.from",Vector3.new(-1592.258,1519.9026,virtualtestingaltitude),sp.wingedge.from.getLocation(),0.1);
    TestUtil.assertVector3("wingedge.to",Vector3.new(-1591.56,1499.9138,virtualtestingaltitude),sp.wingedge.to.getLocation(),0.1);
    TestUtil.assertFloat("wingedge.length", MINIMUMPATHSEGMENTLEN, sp.wingedge.getLength(),0.1);            
    TestUtil.assertVector3("wingreturn1.from",Vector3.new(-1591.211,1489.919,virtualtestingaltitude),sp.wingreturn1.from.getLocation(),0.1);
    TestUtil.assertVector3("wingreturn1.to",Vector3.new(-1572.19,1483.7386,virtualtestingaltitude),sp.wingreturn1.to.getLocation(),0.1);

    var wingapproachlen = sp.wingapproach.getLength();
    TestUtil.assertFloat("wingapproachlen", 30, wingapproachlen);
    TestUtil.assertVector2("prjrearpoint",Vector2.new(-1570.4719,1522.2318),sp.prjrearpoint,0.2);
    var doorbranchedgelen = sp.doorbranchedge.getLength();
    TestUtil.assertFloat("doorbranchedgelen", 152.25296, doorbranchedgelen,0.1);
    var wingbranchedgelen = sp.wingbranchedge.getLength();
    TestUtil.assertFloat("wingbranchedgelen", 129.43648, wingbranchedgelen,0.1);
    TestUtil.assertEquals("wingbestHitEdge", "134-124(134->124)", sp.wingbestHitEdge.toString());

    # fuel truck approach. 
    var start = GraphPosition.new(groundnet.groundnetgraph.findEdgeByName("129-130"));
    # first without smoothing.
    var path = sp.getApproach(start, sp.wingedge.to, 0);
    TestUtil.assertEquals("path", "130:130-131->131-132(107)->bypass(62)->134-124(93)->branchedge(129)->wingapproach(30)->wingedge(20)", path.toString());
    groundnet.groundnetgraph.removeLayer(path.layer);
    # back path
    path = sp.getWingReturnPath(0);
    TestUtil.assertEquals("path", "outernode:return0->return1(20)->bypass(47)->bypass(110)->bypass(106)->132-133(48)->131-132(107)->130-131(27)->129-130(169)->129-68(91)->68-69(21)->63-69(59)->1-63(28)", path.toString());
    groundnet.groundnetgraph.removeLayer(path.layer);
    
    path = sp.getWingReturnPath(true);
    TestUtil.assertEquals("path", "outernode:smoothbegin.->smootharc(12)->smoothbegin.ex(6)->smootharc(12)->smoothbegin.104(34)->smootharc(11)->smoothbegin.124(91)->smootharc(18)->smoothbegin.133(93)->smootharc(0)->smoothbegin.132(48)->smootharc(0)->smoothbegin.131(107)->smootharc(0)->smoothbegin.130(27)->smootharc(0)->smoothbegin.129(160)->smootharc(14)->smoothbegin.68(83)->smootharc(0)->smoothbegin.69(14)->smootharc(12)->smoothbegin.63(52)->smootharc(0)->smoothend.63(28)", path.toString());
    groundnet.groundnetgraph.removeLayer(path.layer);
            
    sp.delete();
    TestUtil.assertEquals("edges", 269, groundnet.groundnetgraph.getEdgeCount());           
    logging.debug("finished testServicePoint737_C4");
}

var maintest = func {
	logging.debug("running maintest");
	unittesting = 1;
	
	miscTest();
    groundnetEDDKTest();
    groundnetOtherTest();
    testServicePoint747_B2();
    testServicePoint737_C4();
    logging.debug("maintest completed");
    cleanupTest();
    unittesting = 0;
};

var cleanupTest = func() {
    schedulesN.removeChildren("schedule");
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