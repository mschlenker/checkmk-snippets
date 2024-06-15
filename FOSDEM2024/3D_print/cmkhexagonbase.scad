$fn = 180;

difference() {
    hull() {
        translate([0,0,0]) cube([50,40,1], true);
        translate([0,0,22]) cube([50,25,1], true);
    }
    union() {
        translate([-24,0,51.5]) rotate(a=[0,90,0]) cylinder(50, 40, 40);
        translate([-26,0,51.5]) rotate(a=[0,90,0]) cylinder(r=50, h=11, $fn=6);
        translate([-26,0,2]) rotate(a=[0,90,0]) cylinder(11, 0.75, 0.75);
    }
}