
#Abstract
This is a proof of concept prototype for a ground service module (subsequently called "GroundServices") for the free flight simulatior FlightGear. Unlike some exisiting ground services
which are part of various aircraft, it is intended to be generic and not dependant on specific aircrafts (though there will be dependencies from aircraft dimensions).
It currently only moves ground vehicles along an airports taxiways without providing any services.
It is written completely in Nasal and is derived/inspired from the existing AI subsystem and tanker.nas (except for the way vehicles are moving).

#Description
After starting FG, GroundServices goes to "standby" mode, monitoring the distance of the main aircraft to the next airport. When the distance is below 3 nm (main.minairportrange), 
GroundService switches to "active" mode. It reads the corresponding groundnet.xml and stores the groundnet in a graph data structure. For simplification
the coordinates are projected to a 2D xy coordinate system, where all calculations are executed (The projection currently is a too
simple linear projection).

Ground vehicles are launched as defined in AI/groundservices.xml.
"initialcount" vehicles of each type will be launched at their defined home location and move between the listed destinations (random groundnet nodes are used if nothing is configured).
Moving of vehicles is implemented by first finding a path along the graph (Graph.findPath()), which is quite simple due to Edsger Dijkstras preliminary work. The vehicles will move along
their defined path like a train on rails. They will allways be fixed at some specific position on some edge (class GraphPosition).
For accomplishing a smooth transition from one edge to the other, the graph not only allows line edges but also arc edges. So the shortest path found through the graph will be smoothed
(GraphUtils.createPathFromGraphPosition() and GraphUtils.createTransition()) by truncating line edges and connecting these by arc edges. These graph edges will be added temporarily to the graph and will be removed from the
graph when the vehicle reaches its destination. Smoothing the graph path is a quite complex process with many potential combinations (eg. short edges, small angles between edges, orientation of vehicles).  
Optimizing this process still is a work in progress. 

When the distance to the airport exceeds 3 nm, GroundServices switches back to "standby" mode, removing all ground vehicles.

The models included are

* the standard Goldhofert pushback truck with aircraftspecific animations removed
* the followme car from FG Addon 

The GUI provides the options to
* launch an additional vehicle (select in combo box and button "Launch")
* visualize the groundnet (which is implemented quite inefficiently by multiple models for each length due to the lack of dynamic model scaling). The color
of the groundnet lines should be yellow, but differs for some unknown reason (lighting effects?) from red to orange.
* show the state of each vehicle

#Requirements
GroundServices was developed and tested with FlightGear 2016.4.3 and EDDKs an EHAMs groundnet. There are no known special requirements and it should also work with other FlightGear versions 
and airports that have a groundnet defined. 

#Configuration
The main configuration file is AI/groundservices.xml. When no home position is defined for an airport, the first
parking node will be used as home.

#Installation
GroundServices is installed by just unpacking the zip file into a FG_ROOT folder. You might backup the folder previously, because there is no real uninstall.
Choose a "no overwrite" option for avoiding overwriting existing files, though no name conflicts are known currently.

In preferences.xml an entry is required for AI/groundservices.xml:
```
  <ai>
      ...
      <groundnet-cache type="bool">true</groundnet-cache>
      <tankers include="AI/tankers.xml"/>
      <groundservices include="AI/groundservices.xml"/>    
  </ai>
```
and in menubar.xml in the AI section (eg. below of the jetway entry):
```
  <item>
        <name>GroundServices</name>
        <enabled>true</enabled>
        <binding>
            <command>dialog-show</command>
            <dialog-name>groundservices</dialog-name>
        </binding>
  </item>
```

After starting FG with the aircraft located on an airport (I propose using ufo on EDDK for a first attempt) open the menu AI->GroundServices and press "Show Status". It should list
8 vehicles in the ATC messages area. In EDDK vehicles will move near the main terminal and should 
be easily visible. EHAM is considerably larger and has no home configured. Vehicles will start from cargo position R, which is in the south west
of the airport. Move ufo near there (by PHI; thats very easy) for seeing the vehicles. 

If any problems occur, check FGs logfiles for nasal errors. In addition
a logfile FG_HOME/nasal.log is written by GroundService and can be checked for errors.

##Uninstall
Uninstallation is done by manually removing the files extracted from the zip file or by restoring FG_ROOT from a backup.

#Current Status
GroundServices currently only moves ground vehicles along an airports taxiways without providing any services.
Its just a prototype and problably contains a lot of bugs. The longer it runs, the risk of
a null/nil pointer increases. Indicator for this is when all vehicles stop moving. Reloading
the module from the GUI can be used for reiniting GroundService quickly.



