

$fn = 120;
boreheight = 8.5;

difference() {
    union() {
        translate([0,0,2]) cylinder(r=50, h=10, $fn=6);
        cylinder(2, 48.5, 50, $fn=6);
    }
    union() {
        translate([0,0,2]) cylinder(r=45, h=24, $fn=6);
        translate([0,0,2]) cylinder(r=40, h=24);
        /*
        translate([0,0,boreheight]) rotate(a=[-90,0,0])
            cylinder(150, 1.75, 1.75, center=true);
        translate([0,0,boreheight]) rotate(a=[-90,0,60])
            cylinder(150, 1.75, 1.75, center=true);
        translate([0,0,boreheight]) rotate(a=[-90,0,-60])
            cylinder(150, 1.75, 1.75, center=true); */
        
    }
}