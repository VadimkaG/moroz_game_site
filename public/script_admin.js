'use strict';
document.addEventListener('DOMContentLoaded', () => {
	const status_wrapper = document.getElementById('status');
	switch (status_wrapper.innerText) {
	case 'not_ready':
		document.getElementById('status_not_ready').style = "";
		break;
	case 'started':
		document.getElementById('stop_game').style = "";
		break;
	case 'ready':
		document.getElementById('start_game').style = "";
		break;
	}
});