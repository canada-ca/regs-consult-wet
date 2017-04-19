/*
 * Web Experience Toolkit (WET) / Boîte à outils de l'expérience Web (BOEW)
 * wet-boew.github.io/wet-boew/License-en.html / wet-boew.github.io/wet-boew/Licence-fr.html
 */
;$(document).ready(

    function() {
        "use strict";
      
        function init_multifield(butt, butttwo) {

           
//            $(document).ready(function () {
                $(document).on('click', '#setStatus', function (e) {
                    e.preventDefault();
                    // Get some values from elements on the comment:
                    var det = $(e.target).attr("data-command");
                    if (typeof  det == "undefined") {
                        det = "request";
                    }
                    var commentaryid =  $("#commentarysummary").attr("data-commentaryid");
                    var mySelection = $(e.target).closest("div").find("#commentary-status").find(":selected").val();
                    var url = "/receive/commentaries/" + commentaryid + "/" + det + "/";
                    // Send the data using post
                    var posting = $.ajax({
                    type: "POST",
                    url: url,
                    xhrFields: {
                    withCredentials: true
                        },
                        // The key needs to match your method's input parameter (case-sensitive).
                    data: JSON.stringify({ "commentary":{
                        "status": mySelection
                        } }),
                    contentType: "application/json; charset=utf-8",
                    dataType: "json",
                    success: function(data){
//                        interfaceUpdate(data);
                        var overlay = data["commentary"];
                        if (typeof  overlay != "undefined") {
                            $("#cty-status").find("strong").text(overlay["status"]);
//                            $( "#submit-panel" ).trigger( "open.wb-overlay" );
                        }

                        
                    },
                    error: function(errMsg) {
                        
                    }
                        });

                    return false;
                });
//            });

        }

        init_multifield("#commentform","#commentpreview");

        
    });
