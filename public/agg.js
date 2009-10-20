function showStuff() {
  var req = new XMLHttpRequest();
  req.open("GET", "/json", true);
  req.onreadystatechange = function() {
    if (req.readyState != 4) {
      return;
    }
    gotStuff(req.status, req.responseText);
  };
  req.send(null);
}

function gotStuff(status, text) {
  if (status != 200) {
    window.setTimeout(showStuff, 5000);
    return;
  }

  var content = "";
  var items = eval(text);
  if (items.length == 0) {
    content = "Nothing yet.\n"
  } else {
    var step = 90 / items.length
    content += "<ul>\n";	  
    for (var i = 0; i < items.length; ++i) {
      var value = 100 - (step * i);
      var opa = value == 100 ? "1" : "0." + parseInt(value);
      content += '<li class="lien" style="background-image: url(/images/' + 
                 items[i].status + '.png)"' + 'title="' + items[i].status + '">';
      content += '<span style="opacity: ' + opa + '">';
      if (i < 3) { content += "<strong>"; }
      content += '<big><a href="/user/' + items[i].nick + '">' + 
                 items[i].nick + '</a></big>: ';
      if (items[i].message != '') {
        content += ' (' + items[i].message + ')';
      }
      content += ' <small title="' + items[i].time  + 
                 '">' + items[i].since + " ago</small></li>";
      if (i < 3) { content += "</strong>"; }
      content += "</span>\n";
    }
    content += "</ul>\n";
    
  }

  document.getElementById("entries").innerHTML = content;
  window.setTimeout(showStuff, 5000);
}

window.onload = showStuff;
