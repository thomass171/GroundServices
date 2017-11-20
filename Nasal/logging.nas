#
#
#

var first = 1;
#var logfilename = "nasal.log";
var logfilename = "groundservices.log";

var logwrite = func (level,msg){
    var currenttime = math.round(systime());
    var seconds = math.mod(math.round(currenttime ), 60);
    var minute = math.mod(math.round(currenttime / (60)), 60);
    var hour = math.mod(math.round(currenttime / (60*60)), 24);
    var filename = props.getNode("/sim/fg-home").getValue() ~ "/" ~ logfilename;
    var logfp = nil;
    if (first) {
        first = 0;
        logfp = io.open(filename, mode="w");
        io.close(logfp);
    }
    var logfp = io.open(filename, mode="a");
    io.write(logfp,sprintf("%02d:%02d:%02d %s ", hour,minute,seconds,level) ~ msg ~ "\n");
    io.close(logfp);
}


var debug = func(msg){
    logwrite("DEBUG",msg);
}

var info = func(msg){
    logwrite("INFO ",msg);
}

var warn = func(msg){
    logwrite("WARN ",msg);
}

var error = func(msg){
    logwrite("ERROR", msg);
}