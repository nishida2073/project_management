(function () {
  document.querySelectorAll('.toggle-row').forEach(function (row) {
    var toggle = row.querySelector('.toggle');
    var label = row.querySelector('span');
    if (!toggle || !label) return;

    var onText = row.getAttribute('data-on') || OperatingStatusStore.labelOf('ACTIVE');
    var offText = row.getAttribute('data-off') || OperatingStatusStore.labelOf('STOPPED');

    toggle.addEventListener('click', function () {
      var isOn = !toggle.classList.contains('off');
      toggle.classList.toggle('off', isOn);
      label.textContent = isOn ? offText : onText;
    });
  });
})();
