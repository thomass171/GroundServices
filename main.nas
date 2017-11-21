
var main = func( root ) {
    
    # logger defines global instance "logging"
    io.load_nasal(root ~ "/Nasal/groundservices/logger.nas","groundservices");
    
    var files =
            ['main.nas','maintest.nas','util.nas','GroundVehicle.nas','GroundService.nas','Groundnet.nas','Graph.nas',
            'mathutil.nas','GroundServiceVisualizer.nas', 'GraphUtils.nas'];
    
    foreach (f;files) {
        io.load_nasal(root ~ "/Nasal/groundservices/" ~ f,"groundservices");
    }
    
    groundservices.root = root;
    groundservices.reinit();
    
    setlistener("/sim/signals/reinit", func() {
        #reinit also performs shutdown if required
        groundservices.reinit();
    });
    
    setlistener("/sim/signals/exit", func() {
        #nothing to do
    });
    
    #TODO proper setup/cleanup as described in http://wiki.flightgear.org/Addons
    printlog("alert","GroundServices addon initialized from path", root );       
}
