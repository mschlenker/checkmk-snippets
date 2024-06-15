$fn = 180;

difference() {
    union() {
        translate([0,0,20]) cube([15,15,40], true);
        
    }
    union() {
        translate([0,44.5,-1]) cylinder(50, 40, 40);
        translate([0,-44.5,-1]) cylinder(50, 40, 40);
        translate([0,25,10]) rotate(a=[90,0,0]) cylinder(50, 2.25, 2.25);
        /* translate([-24,0,51.5]) rotate(a=[0,90,0]) cylinder(50, 40, 40);
        translate([-26,0,51.5]) rotate(a=[0,90,0]) cylinder(r=50, h=11, $fn=6);
        translate([-26,0,2]) rotate(a=[0,90,0]) cylinder(11, 0.75, 0.75); */
    }
}