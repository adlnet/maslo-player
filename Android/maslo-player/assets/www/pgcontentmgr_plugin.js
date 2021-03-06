/******************************************************************************
 * pgcontentmgr_plugin.js
 *
 * Copyright (c) 2011-2012, Academic ADL Co-Lab, University of Wisconsin-Extension
 * http://www.academiccolab.org/
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
 * MA 02110-1301  USA
 *****************************************************************************/

function PGContentManagement() {
}

PGContentManagement.prototype.init = function(success, failure){
    cordova.exec(success, failure, "PGContentManagement", "initializeDatabase", []);
    //cordova.exec(success, failure,
      //            "PGContentManagement", "getContentPath",[]);
    
    return false;
}

PGContentManagement.prototype.updateContent = 
function(success, failure, url,destFileName,title, version) {
    var data = "None yet";
    var processedURL = url.replace(/\\ /g, "%20");
    var downloadSuccess = function(data){    	 
    	 var cont = function(){
    	 	cordova.exec(success, failure,
                     "PGContentManagement", "unzipContent", 
                     [data,title, version]);
    	 }
         cordova.exec(cont, failure, "PGContentManagement" ,"removeContent", [title]);
         
    }
    cordova.exec(downloadSuccess, failure,
                 "PGContentManagement", "downloadContent", 
                 [processedURL,destFileName,title, version, false]);
    return data;
}

PGContentManagement.prototype.downloadContent = 
  function(success, failure, url,destFileName,title,version,wantUnzip) {
    var wantUZip = "false";
    if (wantUnzip != null) {
        if (wantUnzip)
            wantUZip = "true";
    }
    var data = "None yet";
    var processedURL = url.replace(/\\ /g, "%20");    
    cordova.exec(success, failure,
                              "PGContentManagement", "downloadContent", 
                              [processedURL,destFileName,title,version,wantUZip]);
    return data;
}

PGContentManagement.prototype.deleteContent = function(path) {
	var success = function(){return false;}
	var failure = function(){myAlert("error");return false;}
    cordova.exec(success,failure, "PGContentManagement", "removeContent", [path]);
}

PGContentManagement.prototype.getContentList = function(success, fail) {
   return cordova.exec(success, fail, "PGContentManagement", 
                        "getCurrentContentList", []);
}

PGContentManagement.prototype.searchLocally = 
    function(success, failure, query, title) {
    	var lst = [query];
    	if (title != null)
    		lst.push(title);
    	else 
    		lst.push("");
        cordova.exec(success, failure, "PGContentManagement", "searchLocally",
                      lst);
    
    }

PGContentManagement.prototype.PGContentManagementComplete = function(data) {
    myAlert(data);
}



if(!window.plugins) {
    window.plugins = {};
}
if (!window.plugins.fileDownloadMgr) {
    window.plugins.fileDownloadMgr = new PGContentManagement();
}

