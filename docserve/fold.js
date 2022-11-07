/* Test for folding */

var menu = document.getElementsByClassName("main-nav__content")[0];
var subheaders = menu.getElementsByClassName("sect2");

for (var i=0; i<subheaders.length; i++) {
	// The heading:
	var h = subheaders[i].getElementsByTagName("h3")[0];
	// connect an onClick handler to each heading:
	h.addEventListener('click', handleSubFolderClick, false);
	h.style.cursor = "pointer";
}

function handleSubFolderClick() {
	// console.log(this.innerHTML);
	var list = this.parentNode.getElementsByTagName("ul")[0];
	if (list.style.display == "none") {
		list.style.display = "block";
	} else {
		list.style.display = "none";
	}
}

/*
In deeply nested menues, collapse all siblings.
*/

function foldAllSiblings() {
	for (var i=0; i<subheaders.length; i++) {
		var h3 = subheaders[i].getElementsByTagName("h3")[0];
		console.log(h3.getAttribute("id"));
		// Now find the selected item
		var items = subheaders[i].getElementsByClassName("selected");
		if (items.length < 1) {
			// console.log("Found: " + items[0]);
			var list = h3.parentNode.getElementsByTagName("ul")[0];
			list.style.display = "none";
		}
	}
}

window.addEventListener('load', (event) => { foldAllSiblings(); });
