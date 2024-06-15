$fn = 180;

difference() {
    hull() {
        cylinder(7.4, 3.7, 3.7);
        translate([-3.7,-5.2,3.1]) rotate(a=[0,90,0]) cylinder(7.4, 3.1, 3.1);
        translate([-0,-4.1,0.5]) cube(size=[7.4,6.2,1], center=true);
    }
    union() {
        translate([-0,-0,-0.1]) cylinder(7.8, 2.1, 2.1);
        translate([-3.8,-5.2,3.1]) rotate(a=[0,90,0]) cylinder(7.8, 1.5, 1.5);
    }
}