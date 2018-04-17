#
#
#

logging.debug("executing GroundServiceVisualizer.nas");

var groundnetmodel = [];
var visualizer = nil;
var maplayerinitialized = 0;

var visualizeGroundnet = func() {
    removeGroundnetModel();
    # this is also called through listener during reload? Then there is no visualizegroundnetNode
    if (visualizegroundnetNode == nil){
        return;
    }
    var mode = visualizegroundnetNode.getValue();
    logging.debug("visualizeGroundnet: adding groundnet overlay. mode="~mode);
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
        model = root ~ "/Models/GroundServices/markerpool/segment"~segment~".ac";
    } else {
        model = props.globals.getNode("/sim/ai/groundservices/marker["~markerindex~"]/model",1).getValue();
    }
    var coord = projection.unproject(locationXYZ);
    var alt = locationXYZ.z;
    #logging.debug("setMarkerAtLocation: "~model~" "~coord.lat()~" "~coord.lon()~", alt="~alt);
    coord.set_alt(alt);# parameter is meter);
    append(groundnetmodel,geo.put_model(model, coord, heading));
}

var openMap = func() {
    if (!maplayerinitialized) {
        logging.info("adding mapstructure layer");
        var dir = root ~ "/Nasal/canvasmap";
        canvas.MapStructure.loadFile(dir~"/GROUNDSERVICES-net.lcontroller", "GROUNDSERVICES-net");
        canvas.MapStructure.loadFile(dir~"/GROUNDSERVICES-net.symbol", "GROUNDSERVICES-net");
        canvas.MapStructure.loadFile(dir~"/GROUNDSERVICES-vehicle.lcontroller", "GROUNDSERVICES-vehicle");
        canvas.MapStructure.loadFile(dir~"/GROUNDSERVICES-vehicle.symbol", "GROUNDSERVICES-vehicle");
        append(canvas.Map.Controller.get("Aircraft position").update_quickly,"GROUNDSERVICES-vehicle");
        logging.info("mapstructure layer added");
        maplayerinitialized = 1;
    }
    
    var (width, height) = (512,512);
    var myCanvas = canvas.new({
        "name": "Ground Services",   # The name is optional but allow for easier identification
        "size": [width, height], # Size of the underlying texture (should be a power of 2, required) [Resolution]
        "view": [width, height],  # Virtual resolution (Defines the coordinate system of the canvas [Dimensions]
                        # which will be stretched the size of the texture, required)
        "mipmapping": 1       # Enable mipmapping (optional)
    });

    myCanvas.set("background", canvas.style.getColor("bg_color"));
    # creating the top-level/root group which will contain all other elements/group
    var root = myCanvas.createGroup();

    # "dialog" is a type, not a name
    var window = canvas.Window.new([width,height],"dialog");
    window.setCanvas(myCanvas);
    window.setTitle("Ground Services");
    
    var myLayout = canvas.VBoxLayout.new();
    # assign it to the Canvas
    myCanvas.setLayout(myLayout);
    var map = root.createChild("map");
       
    var canvascontroller = 0;
    if (canvascontroller) {
        var button = canvas.gui.widgets.Button.new(root, canvas.style, {})
            .setText("+")
            .setCheckable(1) # this indicates that is should be a toggle button
            .setChecked(0) # depressed by default
            .setFixedSize(20, 20);
        
        button.listen("toggled", func (e) {
            if( e.detail.checked ) {
                logging.debug("depressed");
                map.setRange(map.getRange()+10);
            } else {
                # add code here to react on button not being depressed.
            }
        });        
        myLayout.addItem(button);
        button = canvas.gui.widgets.Button.new(root, canvas.style, {})
            .setText("-")
            .setCheckable(1) # this indicates that is should be a toggle button
            .setChecked(0) # depressed by default
            .setFixedSize(20, 20);
            
            button.listen("toggled", func (e) {
                if( e.detail.checked ) {
                    logging.debug("depressed");
                    map.setRange(map.getRange()-10);
                } else {
                    # add code here to react on button not being depressed.
                }
            });        
        myLayout.addItem(button);
    }
    
    map.setController("Aircraft position");
    map.setRange(maprangeNode.getValue());      
    map.setTranslation(myCanvas.get("view[0]")/2, myCanvas.get("view[1]")/2);
    var r = func(name,vis=1,zindex=nil) return caller(0)[0];
    
    foreach(var type; [r('APT'), r('GROUNDSERVICES-vehicle'), r('GROUNDSERVICES-net') ] ) {
        map.addLayer(factory: canvas.SymbolLayer, type_arg: type.name, visible: type.vis, priority: type.zindex,);
    }
     
    setlistener(maprangeNode, func {
         logging.debug("main: maprangeNode listener fired");
         #not used currently initremoteeventhandler();
         map.setRange(maprangeNode.getValue());
     });
     
    #doesnt work myCanvas.addEventListener("wheel", func(e) {
        #logging.debug("wheel"~e.deltaY);
        #map.setRange(map.getRange()+e.deltaY);
    #});
    var offset = [0,0];
    myCanvas.addEventListener("drag", func(e) {
        logging.debug("drag"~e.deltaY); 
        offset[0] += e.deltaX;
        offset[1] += e.deltaY;
        map.setTranslation((myCanvas.get("view[0]")/2) + offset[0], (myCanvas.get("view[1]")/2) + offset[1]);       
    }); 
    #myCanvas.addEventListener("click", func(e) {
    #    logging.debug("click "~e.deltaY);        
    #}); 
    #myCanvas.addEventListener("mouseover", func(e) {
    #    logging.debug("mouseover "~e.deltaY);        
    #});            
};

#<view n="230">
#  <name>TSCH Test Model View</name>
#  <enabled type="bool" userarchive="y">true</enabled>
#  <type>lookfrom</type>
#  <config>
#    <eye-lat-deg-path>/ai/models/gsvehicle[2]/position/latitude-deg</eye-lat-deg-path>
#    <eye-lon-deg-path>/ai/models/gsvehicle[2]/position/longitude-deg</eye-lon-deg-path>
#    <eye-alt-ft-path>/ai/models/gsvehicle[2]/position/altitude-ft</eye-alt-ft-path>
#    <eye-roll-deg-path>/sim/tower/roll-deg</eye-roll-deg-path>
#    <eye-pitch-deg-path>/sim/tower/pitch-deg</eye-pitch-deg-path>
#    <eye-heading-deg-path>/sim/tower/heading-deg</eye-heading-deg-path>
#    <ground-level-nearplane-m type="double">10.0f</ground-level-nearplane-m>
#    <default-field-of-view-deg type="double">55.0</default-field-of-view-deg>
#    <x-offset-m type="double">0</x-offset-m>
#    <y-offset-m type="double">0</y-offset-m>
#    <z-offset-m type="double">0</z-offset-m>
#  </config>
#</view>

#
# Apparently its neither possible to dynamically add new views nor to use parameter "from-model-idx".
# So a basic static view point is used and adjusted.->Useless efforts
#var buildView = func() {
 #   logging.debug("setting view");
    # index will be the next one after the last
    #var viewN = props.globals.getNode("/sim",0).addChild("view");
  #  setprop("/sim/current-view/view-number", 9);

    #return;
    
   # var viewN = props.globals.getNode("/sim/current-view");
    #viewN.addChild("name").setValue("GS View");
    #viewN.addChild("enabled").setBoolValue(1);
    #viewN.addChild("type").setValue("lookfrom");
    #var root = "/ai/models/gsvehicle[2]";
    #viewN.getNode("config",1).setValues({
    #    "eye-lat-deg-path": root ~ "/position/latitude-deg",
    #    "eye-lon-deg-path": root ~ "/position/longitude-deg",
    #    "eye-alt-ft-path": root ~ "/position/altitude-ft",
        #"eye-heading-deg-path": data.root ~ "/orientation/heading-deg",
        #"target-lat-deg-path": data.root ~ "/position/latitude-deg",
        #"target-lon-deg-path": data.root ~ "/position/longitude-deg",
        #"target-alt-ft-path": data.root ~ "/position/altitude-ft",
        #"target-heading-deg-path": data.root ~ "/orientation/heading-deg",
        #"target-pitch-deg-path": data.root ~ "/orientation/pitch-deg",
        #"target-roll-deg-path": data.root ~ "/orientation/roll-deg",
    #});
#}

logging.debug("completed GroundServiceVisualizer.nas");