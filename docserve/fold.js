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