// JS for glossary overlays

var entered_overlay = 0;
var tout;

// Get the container
var artcontent = document.getElementsByTagName("main")[0];
// Traverse all links:
var links = artcontent.getElementsByTagName("a");
for (var i=0; i<links.length; i++) {
	// console.log(links[i].innerHTML);
	var href = links[i].getAttribute("href");
	if (href) {
		if (href.includes("glossar.html#", 0)) {
			links[i].addEventListener('mouseenter', mouseOverGlossary, false);
			links[i].addEventListener('mouseleave', waitOverlayClose, false);
			console.log("Add glossary overlay for: " + href);
		} else if (href.includes("://")) {
			console.log("Ignore protocol link: " + href);
		} else {
			// links[i].addEventListener('mouseenter', mouseOverPreview, false);
			// links[i].addEventListener('mouseleave', waitOverlayClose, false);
			// console.log("Add link overlay for: " + href);
		}
	} else {
		console.log("No href found!");
	}
}

function removeGlossary() {
	var box = document.getElementById("glossary_overlay");
	if (box) {
		box.remove();
	}
	try {
		clearTimeout(tout);
		console.log("Cleared timeout: " + tout);
	} catch (e) {
		console.log("No timeout to clear.");
	}
	entered_overlay = 0;
}

function mightCloseGlossary() {
	if (entered_overlay < 1) {
		removeGlossary();
		console.log("Removed box after given timeout.");
	}
}

function waitOverlayClose() {
	var entry = this.getAttribute("href");
	console.log("Leaving link: " + entry);
	var box = document.getElementById("glossary_overlay");
	if (box) {
		tout = setTimeout(mightCloseGlossary, 500);
	}
}

function enterOverlayBox() {
	entered_overlay = 1;
	console.log("Entered overlay: " + entered_overlay);
}

function exitOverlayBox() {
	// removeGlossary();
	removeGlossary();
	entered_overlay = 0;
	console.log("Exited overlay: " + entered_overlay);
}

function mouseOverGlossary(event) {
	try {
		clearTimeout(tout);
		console.log("Cleared timeout: " + tout);
	} catch (e) {
		console.log("No timeout to clear.");
	}
	var ptoks = window.location.pathname.split("/");
	var entry = this.getAttribute("href").split("#")[1];
	// console.log(entry);
	var xhr = new XMLHttpRequest();
	// var j;
	xhr.open('GET', "/glossary/" + ptoks[2] + "/" + entry, true);
	xhr.overrideMimeType("text/plain; charset=utf8");
	// xhr.responseType = 'json';
	xhr.onload = function() {
		if (xhr.status === 200) {
			displayGlossary(xhr.response, event.clientX, event.clientY);
		}
	}
	xhr.send();
}

function displayGlossary(html, x, y) {
	// Remove a window if it exists
	removeGlossary();
	var winwidth = window.innerWidth;
	var winheight = window.innerHeight;
	var box = document.createElement("div");
	box.setAttribute("id", "glossary_overlay");
	box.innerHTML = html;
	artcontent.appendChild(box);
	box.style.display = "block";
	console.log("Mouse position, x: " + x + ", y: " + y);
	var boxwidth = box.clientWidth;
	var boxheight = box.clientHeight;
	// Check whether we are left or right from the center
	if (x > winwidth / 2) { // right
		box.style.left = (x - boxwidth) + "px";
	} else { // left
		box.style.left = x + "px";
	}
	// Check whether we are higher or lower than the center
	if (y > winheight / 2) { // lower
		box.style.top = (y - boxheight - 10) + "px";
	} else { // higher
		box.style.top = (y + 10) + "px";
	}
	// Add enter event listener for the box
	box.addEventListener('mouseenter', enterOverlayBox, false);
	box.addEventListener('mouseleave', exitOverlayBox, false);
}

function mouseOverPreview(event) {
	try {
		clearTimeout(tout);
		console.log("Cleared timeout: " + tout);
	} catch (e) {
		console.log("No timeout to clear.");
	}
	var target =  this.getAttribute("href").split("#")[0];
	console.log("Entering link to: " + target);
	var xhr = new XMLHttpRequest();
	xhr.open('GET', target, true);
	xhr.responseType = "document";
	xhr.onload = function() {
		if (xhr.status === 200) {
			displayPreview(xhr.responseXML, event.clientX, event.clientY);
		}
	}
	xhr.send();
}

function displayPreview(html, x, y) {
	removeGlossary();
	// console.log(html);
	var title = html.title;
	var description = "";
	metas = html.getElementsByTagName("meta");
	for (i=0; i<metas.length; i++) {
		if (metas[i].getAttribute("name") == "description") {
			description = metas[i].getAttribute("content");
		}
	}
	var winwidth = window.innerWidth;
	var winheight = window.innerHeight;
	var box = document.createElement("div");
	box.setAttribute("id", "glossary_overlay");
	box.innerHTML = "<h4>" + title + "</h4><div class=\"paragraph\"><p>" + description + "</p></div>";
	artcontent.appendChild(box);
	box.style.display = "block";
	console.log("Mouse position, x: " + x + ", y: " + y);
	var boxwidth = box.clientWidth;
	var boxheight = box.clientHeight;
	// Check whether we are left or right from the center
	if (x > winwidth / 2) { // right
		box.style.left = (x - boxwidth) + "px";
	} else { // left
		box.style.left = x + "px";
	}
	// Check whether we are higher or lower than the center
	if (y > winheight / 2) { // lower
		box.style.top = (y - boxheight - 10) + "px";
	} else { // higher
		box.style.top = (y + 10) + "px";
	}
	// Add enter event listener for the box
	box.addEventListener('mouseenter', enterOverlayBox, false);
	box.addEventListener('mouseleave', exitOverlayBox, false);
}

// Open and close featured topic
var featured = document.getElementById("featuredtopic");
featured.addEventListener("click", openFeaturedOverlay, false);

function openFeaturedOverlay() {
	console.log("Clicked on featured"); 
	document.getElementById("topicopaque").style.display = "block";
	return false;
}
function hideFeaturedTopic() {
	document.getElementById("topicopaque").style.display = "none";
	return false;
}
