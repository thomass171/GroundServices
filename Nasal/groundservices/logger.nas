#
#
#

var LOGLEVEL_ERROR = 200;
var LOGLEVEL_WARN = 300;
var LOGLEVEL_INFO = 400;
var LOGLEVEL_DEBUG = 500;

var Logger = {    
	new: func() {	    
	    var obj = { parents: [Logger] };
	    obj.logfilecreated = 0;
	    obj.logfilename = "groundservices.log";
	    obj.loglevel = LOGLEVEL_DEBUG;
	    return obj;
	},	    
    
    logwrite: func (level,msg){
        var currenttime = math.round(systime());
        var seconds = math.mod(currenttime, 60);
        var minute = math.mod(math.floor(currenttime / 60), 60);
        var hour = math.mod(math.floor(currenttime / 3600), 24);
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
        if (me.loglevel >= LOGLEVEL_DEBUG) {
            me.logwrite("DEBUG",msg);
        }
    },
    
    info: func(msg){
        if (me.loglevel >= LOGLEVEL_INFO) {
            me.logwrite("INFO ",msg);
        }
    },
    
    warn: func(msg){
        if (me.loglevel >= LOGLEVEL_WARN) {
            me.logwrite("WARN ",msg);
        }
    },
    
    error: func(msg){
        if (me.loglevel >= LOGLEVEL_ERROR) {
            me.logwrite("ERROR", msg);
        }
    },          	
};

var logging = Logger.new();
