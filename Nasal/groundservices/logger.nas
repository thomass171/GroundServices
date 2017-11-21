#
#
#

var logger = {    
	new: func() {	    
	    var obj = { parents: [logger] };
	    obj.logfilecreated = 0;
	    obj.logfilename = "groundservices.log";
	    return obj;
	},	    
    
    logwrite: func (level,msg){
        var currenttime = systime();
        var seconds = math.mod(math.round(currenttime ), 60);
        var minute = math.mod(math.round(currenttime / (60)), 60);
        var hour = math.mod(math.round(currenttime / (60*60)), 24);
        var filename = props.getNode("/sim/fg-home").getValue() ~ "/" ~ me.logfilename;
        var logfp = nil;
        if (!me.logfilecreated) {
            me.logfilecreated = 1;
            me.logfp = io.open(filename, mode="w");
            io.close(me.logfp);
        }
        var logfp = io.open(filename, mode="a");
        io.write(logfp,sprintf("%02d:%02d:%02d %s ", hour,minute,seconds,level) ~ msg ~ "\n");
        io.close(logfp);
    },    
    
    debug: func(msg){
        me.logwrite("DEBUG",msg);
    },
    
    info: func(msg){
        me.logwrite("INFO ",msg);
    },
    
    warn: func(msg){
        me.logwrite("WARN ",msg);
    },
    
    error: func(msg){
        me.logwrite("ERROR", msg);
    },          	
};

var logging = logger.new();
