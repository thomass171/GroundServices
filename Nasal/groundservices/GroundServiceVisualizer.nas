#
#
#

logging.debug("executing GroundServiceVisualizer.nas");

var groundnetmodel = [];
var visualizer = nil;

var visualizeGroundnet = func() {
    removeGroundnetModel();
    var mode = visualizegroundnetNode.getValue();
    logging.debug("visualizeGroundnet: adding groundnet overlay. mode="~mode);
    if (1) {
        if (mode > 0) {
            for (var i=0;i<groundnet.groundnetgraph.getNodeCount();i+=1){
                var node = groundnet.groundnetgraph.getNode(i);
                var customdata = node['customdata'];
                if (customdata == nil){
                    #setMarkerAtLocation(node.getLocation(),1);
                }else{
                    setMarkerAtLocation(node.getLocation(),2);
                }                                
            }
            foreach (var edge; groundnet.groundnetgraph.edges) {
                if (edge.getLayer()==0){
                    var len = math.round(edge.from.coord.distance_to(edge.to.coord));
                    var heading = edge.from.coord.course_to(edge.to.coord);
                    if (edge.getName()=="131-132"){
                        #logging.debug("heading="~heading);
                    }
                    setMarkerAtLocation(edge.from.getLocation(),-1,len,heading);
                }
            }
        }
    }else{
        # not yet working       
        var path = "Aircraft/ufo/Models/groundnet.ac";
        var course = getprop("/inputgs/heading");
        var pitch = getprop("/inputgs/pitch");
        var roll= getprop("/inputgs/roll");
        logging.debug("heading=" ~ course ~ ",pitch="~pitch~",roll="~roll);
        append(groundnetmodel, geo.put_model(path, center, course,pitch,roll));
        #var earthcenter = geo.Coord.new();
        #earthcenter.set_xyz(0,0,0);
        #groundnetmodel = geo.put_model(path, earthcenter);
        geo.put_model("Models/Export/marker1.ac", center);
    }
}

var removeGroundnetModel = func(){
    foreach (var m;groundnetmodel){
        m.remove();
    }
    #release memory? 
    groundnetmodel = [];    
}

var setMarkerAtLocation = func(locationXYZ,markerindex,segment=-1,heading=0) {
    var model = nil;
    if (markerindex == -1){
        model = "Models/GroundServices/markerpool/segment"~segment~".ac";
    } else {
        model = props.globals.getNode("/sim/ai/groundservices/marker["~markerindex~"]/model",1).getValue();
    }
    var coord = projection.unproject(locationXYZ);
    var alt = getCurrentAltitude();
    #logging.debug("setMarkerAtLocation: "~model~" "~coord.lat()~" "~coord.lon()~", alt="~alt);
    coord.set_alt(alt);# parameter is meter);
    append(groundnetmodel,geo.put_model(model, coord, heading));
}

logging.debug("completed GroundServiceVisualizer.nas");