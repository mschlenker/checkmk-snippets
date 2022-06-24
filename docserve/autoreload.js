// JS snippet to autoreload:

var lastChange = CHANGED;
var checkUrl = "JSONURL";
var autoReload = setInterval(checkForUpdate, 1000);

function checkForUpdate() {
	var xhr = new XMLHttpRequest();
	var j;
	xhr.open('GET', checkUrl, true);
	xhr.responseType = 'json';
	xhr.onload = function() {
		var status = xhr.status;
		if (status === 200) {
			// console.log(xhr.response["last-change"]);
			// console.log(lastChange);
			if (xhr.response["last-change"] > lastChange) {
				console.log("Page has changed, reloading.");
				clearInterval(autoReload);
				location.reload(true);
			}
		} 
	};
	xhr.send();
}
