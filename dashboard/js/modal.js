// js/modal.js — generic modal open/close + a reusable danger-confirmation dialog.
function openModal(id) {
  const el = document.getElementById(id);
  if (el) el.classList.add('on');
}
function closeModal(id) {
  const el = document.getElementById(id);
  if (el) el.classList.remove('on');
}

// Fills #confirm-modal and wires its confirm button for one-off use.
function confirmDanger({ title, body, confirmLabel = 'Confirm', onConfirm }) {
  document.getElementById('cf-title').textContent = title;
  document.getElementById('cf-body').textContent = body;
  const btn = document.getElementById('cf-confirm');
  btn.textContent = confirmLabel;
  btn.onclick = () => {
    closeModal('confirm-modal');
    onConfirm();
  };
  openModal('confirm-modal');
}
