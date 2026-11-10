'use strict';
document.addEventListener('DOMContentLoaded', () => {
	const slides = document.querySelectorAll('.gallery-slide');

	let currentSlide = Math.floor(Math.random() * slides.length);
	slides[currentSlide].classList.add('active');

	setInterval(() => {
		slides[currentSlide].classList.remove('active');
		currentSlide = (currentSlide + 1) % slides.length;
		slides[currentSlide].classList.add('active');
	},8000);

	var modal_showed = false;
	const gallery_hint = document.querySelector('.gallery-hint');
	const modal_overlay = document.querySelector('.modal-overlay');
	document.querySelector('.gallery-container').addEventListener('click', () => {
		if (modal_showed) return;
		modal_showed = true;
		gallery_hint.style="display:none;";
		modal_overlay.classList.add('active');
	});
	modal_overlay.addEventListener('click', (event) => {
		if (event.target === modal_overlay) {
			modal_showed = false;
			modal_overlay.classList.remove('active');
			gallery_hint.style="";
		}
	});

	// Форма
	{
		const field_name = document.getElementById('field__name');
		if (field_name) {
			const field_name__char_count = document.getElementById('field__name__char_count');
			field_name.addEventListener('input',()=>{
				field_name__char_count.textContent = field_name.value.length;
			});
			field_name__char_count.textContent = field_name.value.length;
		}
		const field_message = document.getElementById('field__message');
		if (field_message) {
			const field_message__char_count = document.getElementById('field__message__char_count');
			field_message.addEventListener('input',()=>{
				field_message__char_count.textContent = field_message.value.length;
			});
			field_message__char_count.textContent = field_message.value.length;
		}
		const submit_btn = document.querySelector('button.letter-submit');
		const savedHint = document.querySelector('.letter-hint.saved');
		const errorHint = document.querySelector('.letter-hint.error');
		const readyInput = document.getElementById('field__not_ready');
		let in_senging_state = false;
		if (submit_btn)
		submit_btn.addEventListener('click',async function(){
			if (in_senging_state) return;
			in_senging_state = true;
			const formData = new FormData(document.querySelector('form.letter-form'));
			try {
				const response = await fetch(window.location.href, {
					method: 'POST',
					headers: {
						'Content-Type': 'application/x-www-form-urlencoded'
					},
					body: new URLSearchParams(formData),
				});
				if (response.status !== 200) {
					errorHint.classList.add('active');
					setTimeout(() => errorHint.classList.remove('active'), 3000);
					return;
				}

				if (readyInput?.checked) {
					const savedHint = document.querySelector('.letter-hint.saved');
					savedHint.classList.add('active');
					setTimeout(() => savedHint.classList.remove('active'), 3000);
				} else {
					document.getElementById('letter').style.display = 'none';
					document.getElementById('letter-success').style.display = 'block';
				}
			} catch (error) {
				errorHint.classList.add('active');
				setTimeout(() => errorHint.classList.remove('active'), 3000);
			}
			in_senging_state = false;
		});
	}

	// Страница показа письма
	const myletter = document.getElementById('myletter');
	if (myletter) {
		const letter = document.getElementById('letter');
		const letter_a = document.getElementById('open_myletter');
		const myletter_content = document.getElementById('myletter__content');
		let is_loading = false;
		letter_a.addEventListener('click',(e) =>{
			e.preventDefault();
			if (is_loading)
				return;
			is_loading = true;
			fetch(letter_a.href)
				.then(response => {
					is_loading = false;
					if (!response.ok) {
						throw new Error(`Ошибка: ${response.status}`);
					}
					return response.text();
				})
				.then(htmlString => {
					myletter_content.innerHTML = htmlString;
					letter.style="display:none";
					myletter.style="";
				});
		});
		const comeback_a = document.getElementById('comeback');
		if (comeback_a)
			comeback_a.addEventListener('click',(e)=>{
				e.preventDefault();
				myletter.style="display:none";
				letter.style="";
			});
	}
});