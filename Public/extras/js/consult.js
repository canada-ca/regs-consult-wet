
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

        var texteditboxarea = '<div><textarea form="commentsubmission" class="form-control full-width comment-area" rows="5"  placeholder="' + langfrag.placeh + '"></textarea><ul class="list-inline"><li><button class="btn btn-default save_field" type="button">' + langfrag.save + '</button></li><li><div class="savestatus" aria-hidden="true"></div></li></ul></div>'
        function init_multifield(butt, butttwo) {
            var add_button = $(butt); //Add button class
            var add_button_two = $(butttwo); //Add button class

            var buttonHighlight = function (id, cls) {

                $(id).removeClass( "btn-default btn-primary btn-success" ).addClass( cls);

            }
            var interfaceUpdate = function (data){
                var commty = data["commentary"]
                if (typeof  commty != "undefined") {
                    if (typeof  commty["name"] != "undefined") {
                        $("#commentator-name").val(commty["name"])
                    }
                    if (typeof  commty["organization"] != "undefined") {
                        $("#commentator-org").val(commty["organization"])
                    }
                    if (typeof  commty["email"] != "undefined") {
                        $("#commentator-email").val(commty["email"])
                    }
                    if (typeof  commty["represents"] != "undefined") {
                        $("#commentator-identity").val(commty["represents"])
                    }
                    if (typeof  commty["submitstatus"] != "undefined") {
                        switch (commty["submitstatus"]) {
                            case "ready":
                                buttonHighlight("#comment-submit-button", "btn-primary");
                                buttonHighlight("#comment-submit-buttonalt", "btn-primary");
                                break;
                            case "submitted":
                                buttonHighlight("#comment-submit-button", "btn-success");
                                buttonHighlight("#comment-submit-buttonalt", "btn-success");
                                $("#comment-submit-button").text(langfrag.submitted);
                                $("#comment-submit-buttonalt").text(langfrag.submitted);
                                break;
                            default:
                                buttonHighlight("#comment-submit-button", "btn-default");
                                buttonHighlight("#comment-submit-buttonalt", "btn-default");
                        }
                    }

                }
            }
            var getcommentary = function (tooltype){
                var loadCommentArea = function (selector, text){

                    var selescaped = selector.replace(/[;&,\.\+\*~':"!\^\$\[\]\(\)=>|\/\\]/g, '\\$&'); // had to leave # alone????
                    var sel = $(selescaped);

                    if (sel.has("textarea").length) {

                    } else {
                        sel.append(texteditboxarea); //add input box
                        sel.addClass("commentpresent");
                    }

                    sel.find("textarea").val(text);
                }

                var docid =  $("#commentsummary").attr("data-documentid");
                if (typeof docid == "undefined") {return}
                var url = "/documents/" + docid + "/commentaries/";
                var jqxhr = $.ajax({
                type: "GET",
                url: url,
                contentType: "application/json; charset=utf-8",
                dataType: "json",
                success: function(data){
                    var comms = data["comments"]
                    if (typeof  comms != "undefined") {
                        comms.forEach(function(comment){
                            loadCommentArea("#" + comment["ref"],comment["text"]);
                        });
                        buttonHighlight("#comment-summary-button", "btn-primary");
                        buttonHighlight("#comment-summary-buttonalt", "btn-primary");
                    };
                    interfaceUpdate(data);
                }
                    });
                
            }

            $(add_button).on("click", "summary", function(event) {
                var sel = $(event.target).closest("details");
                if (sel.has("textarea").length) {
                    if ((typeof sel.attr("open")) !== "undefined") {
                        if (sel.find("textarea").val() === "") {

                            sel.removeClass("commentpresent");
                            //           $( event.target ).next("div").remove(); //safari does not like this
                        }
                    } else {
                        sel.addClass("commentpresent");
                    }
                } else {
                    sel.append(texteditboxarea); //add input box
                    sel.addClass("commentpresent");
                }
            });

            $(add_button).on("click", ".comment-area ", function(event) {
                //console.log("btn cont1 event", event)
                var det = $(event.target).closest("details");
                det.find("div.savestatus").replaceWith('<div class="savestatus" aria-hidden="true"></div>');
            });

            var postupdate = function (e){
                e.preventDefault();
                // Get some values from elements on the comment:
                var det = $(e.target).closest("details");
                var refid = det.attr("id");
                var commenttext = det.find("textarea").val();
                var docid =  $("#commentsummary").attr("data-documentid");
                var url = "/documents/" + docid + "/comments/";
                // Send the data using post
                det.find("div.savestatus").replaceWith('<div class="savestatus"><i class="fa fa-cog fa-spin fa-2x fa-fw text-muted" aria-hidden="true"></i><span class="sr-only">' + langfrag.saving + '</span></div>');

                var posting = $.ajax({
                type: "POST",
                url: url,
                    // The key needs to match your method's input parameter (case-sensitive).
                data: JSON.stringify({ "comments":[{
                    "ref": refid,
                    "text": commenttext
                    }] }),
                contentType: "application/json; charset=utf-8",
                dataType: "json",
                success: function(data){det.find("div.savestatus").replaceWith('<div class="savestatus"><i class="fa fa-2x fa-check text-success" aria-hidden="true"></i>  ' + langfrag.saved + '</div>');
                    buttonHighlight("#comment-summary-button", "btn-primary");
                    buttonHighlight("#comment-summary-buttonalt", "btn-primary");
                },
                error: function(jqx,tstatus, errorthrown) {
                    det.find("div.savestatus").replaceWith('<div class="savestatus"><i class="fa fa-2x fa-question-circle text-warning" aria-hidden="true"></i>  ' + langfrag.failedsave + ' - ' + errorthrown + ', ' + langfrag.tryagain + '</div>')
                }
                    });

            }

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

                    },
                    error: function(errMsg) {
                        
                    }
                    });

            }
            var postsubmit = function (e){
                // Get some values from elements on the identity:
                e.preventDefault();
                // Get some values from elements on the comment:
                var det = $(e.target).attr("data-command");
                if (typeof  det == "undefined") {
                    det = "request";
                }

                var docid =  $("#commentsummary").attr("data-documentid");
                var url = "/documents/" + docid + "/commentaries/submit/" + det + "/";
                // Send the data using post
                var posting = $.ajax({
                type: "POST",
                url: url,
                    // The key needs to match your method's input parameter (case-sensitive).
                data: JSON.stringify({ 
                     }),
                contentType: "application/json; charset=utf-8",
                dataType: "json",
                success: function(data){
                    var overlay = data["overlayhtml"]
                    if (typeof  overlay != "undefined") {
                        $("#submit-panel-content").html(overlay);
                        $( "#submit-panel" ).trigger( "open.wb-overlay" );
                    }

                    interfaceUpdate(data);


                },
                error: function(errMsg) {

                }
                    });

            }
            $(add_button).on("change", ".comment-area",  postupdate); //user updated textarea
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

            $(add_button_two).on("click", "h5.comment-edit", function(event) {
                var sel = $(event.target).closest("div").attr("id");
                var doclink =  $("#commentsummary").attr("data-documentlink");
                window.location = doclink + "?#" + encodeURIComponent(sel)
            });

            $(add_button).on("click", ".comment-submit-control", postsubmit);
            
            if ( $('#commentpreview').length == 0) {
                getcommentary();
            }

        }

        init_multifield("#commentform","#commentpreview");


    });
