/*
 * Web Experience Toolkit (WET) / Boîte à outils de l'expérience Web (BOEW)
 * wet-boew.github.io/wet-boew/License-en.html / wet-boew.github.io/wet-boew/Licence-fr.html
 */
;$(document).ready(

    function() {
        "use strict";
        var langfrag;
        if ($("html").attr("lang") == "fr") {
            langfrag = {
            placeh: "Saisissez vos commentaires",
            save: "Enregistrer",
            saving: "Enregistrer un commentaire",
            saved: "Commentaire enregistré",
            failedsave: "N'a pas sauvé",
            tryagain: "Modifier un texte et enregistrer de nouveau.",
            submitted: "Soumis"
            };
        } else {
            langfrag = {
            placeh: "Enter your feedback",
            save: "Save",
            saving: "Saving comment",
            saved: "Comment saved",
            failedsave: "Did not save",
            tryagain: "Alter some text and save again.",
            submitted: "Submitted"
            };
        }

        function init_multifield(butt, butttwo) {
            var postupdateidentity = function (e){
                // Get some values from elements on the identity:

                var commidentity = $("#commentator-identity").val();
                var commname = $("#commentator-name").val();
                var commorg = $("#commentator-org").val();
                var commemail = $("#commentator-email").val();

                var docid =  $("#commentsummary").attr("data-documentid");
                var url = "/documents/" + docid + "/comments/";
                // Send the data using post
                var posting = $.ajax({
                type: "POST",
                url: url,
                xhrFields: {
                withCredentials: true
                    },
                    // The key needs to match your method's input parameter (case-sensitive).
                data: JSON.stringify({ "commentary":{
                    "represents": commidentity,
                    "name": commname,
                    "organization": commorg,
                    "email": commemail
                    } }),
                contentType: "application/json; charset=utf-8",
                dataType: "json",
                success: function(data){
                    interfaceUpdate(data);
                    var overlay = data["overlayhtml"];
                    if (typeof  overlay != "undefined") {
                        $("#submit-panel-content").html(overlay);
                        $( "#submit-panel" ).trigger( "open.wb-overlay" );
                    }


                },
                error: function(errMsg) {

                }
                    });

            }
            $(".commentator").on("change",  postupdateidentity);

            $('#toggle-fulltext').change(function() {
                if ($(this).prop('checked')){
                    $('#commentpreview').removeClass("hideorigtext")
                } else{
                    $('#commentpreview').addClass("hideorigtext");
                    $( ".wb-eqht" ).trigger( "wb-update.wb-eqht" );
                }
            });
            $('#toggle-emptycomments').change(function() {
                if ($(this).prop('checked')){
                    $('#commentpreview').removeClass("hideempty")
                } else{
                    $('#commentpreview').addClass("hideempty")
                }
            });

//            $(add_button_two).on("click", "h5.comment-edit", function(event) {
//                var sel = $(event.target).closest("div").attr("id");
//                var doclink =  $("#commentsummary").attr("data-documentlink");
//                window.location = doclink + "?#" + encodeURIComponent(sel)
//            });
//            
//            $(add_button).on("click", ".comment-submit-control", postsubmit);
//            
//            if ( $('#commentpreview').length == 0) {
//                getcommentary();
//            }

            $(document).ready(function () {
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
            });

        }

        init_multifield("#commentform","#commentpreview");

        
    });
