(in-package :cgl)

;; :color-attachmenti :depth-attachment :stencil-attachment :depth-stencil-attachment

;; NOTE: The second parameter implies that you can have multiple color
;; attachments. A fragment shader can output different data to any of these by
;; linking out variables to attachments with the glBindFragDataLocation
;; function

;; Framebuffer Object Structure

(defstruct (fbo (:constructor %make-fbo)
                (:conc-name %fbo-))
  id)

(defun make-fbo (&key initial-attachment)
  (let ((fbo (%make-fbo :id (first (gl:gen-framebuffers 1)))))
    (when initial-attachment
      (fbo-attach fbo initial-attachment :color-attachment0))
    fbo))

(defun make-fbos (&optional (count 1))
  (unless (> count 0)
    (error "Attempting to create invalid number of framebuffers: ~s" count))
  (%make-fbo :id (gl:gen-framebuffers 1)))

(defun %delete-fbo (fbo)
  (gl:delete-framebuffers (listify (%fbo-id fbo))))

(defun %delete-fbos (&rest fbos)
  (gl:delete-framebuffers (mapcar #'%fbo-id fbos)))

(defun %bind-fbo (fbo target)
  ;; The target parameter for this object can take one of 3 values:
  ;; GL_FRAMEBUFFER, GL_READ_FRAMEBUFFER, or GL_DRAW_FRAMEBUFFER.
  ;; The last two allow you to bind an FBO so that reading commands
  ;; (glReadPixels, etc) and writing commands (any command of the form glDraw*)
  ;; can happen to two different buffers.
  ;; The GL_FRAMEBUFFER target simply sets both the read and the write to the
  ;; same FBO.
  ;; When an FBO is bound to a target, the available surfaces change.
  ;; The default framebuffer has buffers like GL_FRONT, GL_BACK, GL_AUXi,
  ;; GL_ACCUM, and so forth. FBOs do not have these.
  ;; Instead, FBOs have a different set of images. Each FBO image represents an
  ;; attachment point, a location in the FBO where an image can be attached.
  (gl:bind-framebuffer target (%fbo-id fbo)))

(defun %unbind-fbo ()
  (gl:bind-framebuffer :framebuffer 0))

(defmacro with-bind-fbo ((fbo target &optional (unbind t)) &body body)
  `(progn (%bind-fbo ,fbo ,target)
          ,@body
          ,(when unbind `(%unbind-fbo))))

;; Attaching Images

;; Remember that textures are a set of images. Textures can have mipmaps; thus,
;; each individual mipmap level can contain one or more images.

(defun fbo-attach (fbo tex-array attachment &optional (target :draw-framebuffer))
  ;; To attach images to an FBO, we must first bind the FBO to the context.
  ;; target can be '(:framebuffer :read-framebuffer :draw-framebuffer)
  (with-bind-fbo (fbo target)
    ;; FBOs have the following attachment points:
    ;; GL_COLOR_ATTACHMENTi: These are an implementation-dependent number of
    ;; attachment points. You can query GL_MAX_COLOR_ATTACHMENTS to determine the
    ;; number of color attachments that an implementation will allow. The minimum
    ;; value for this is 1, so you are guaranteed to be able to have at least
    ;; color attachment 0. These attachment points can only have images bound to
    ;; them with color-renderable formats. All compressed image formats are not
    ;; color-renderable, and thus cannot be attached to an FBO.
    ;;
    ;; GL_DEPTH_ATTACHMENT: This attachment point can only have images with depth
    ;; formats bound to it. The image attached becomes the Depth Buffer for
    ;; the FBO.
    ;;
    ;; GL_STENCIL_ATTACHMENT: This attachment point can only have images with
    ;; stencil formats bound to it. The image attached becomes the stencil buffer
    ;; for the FBO.
    ;;
    ;; GL_DEPTH_STENCIL_ATTACHMENT: This is shorthand for "both depth and stencil"
    ;; The image attached becomes both the depth and stencil buffers.
    ;; Note: If you use GL_DEPTH_STENCIL_ATTACHMENT, you should use a packed
    ;; depth-stencil internal format for the texture or renderbuffer you are
    ;; attaching.
    ;;
    ;; When attaching a non-cubemap, textarget should be the proper
    ;; texture-type: GL_TEXTURE_1D, GL_TEXTURE_2D_MULTISAMPLE, etc.
    (with-slots (texture-type dimensions (mipmap-level level-num) layer-num
                              face-num internal-format texture) tex-array
      (unless (attachment-compatible fbo internal-format)
        (error "attachment is not compatible with this array"))
      (let ((tex-id (slot-value texture 'texture-id)))
        (case (texture-type tex-array)
          ;; A 1D texture contains 2D images that have the vertical height of 1.
          ;; Each individual image can be uniquely identified by a mipmap level.
          (:texture-1d (gl:framebuffer-texture-1d target attachment :texture-1d
                                                  tex-id mipmap-level))
          ;; A 2D texture contains 2D images. Each individual image can be
          ;; uniquely identified by a mipmap level.
          (:texture-2d (gl:framebuffer-texture-2d target attachment :texture-2d
                                                  tex-id mipmap-level))
          ;; Each mipmap level of a 3D texture is considered a set of 2D images,
          ;; with the number of these being the extent of the Z coordinate.
          ;; Each integer value for the depth of a 3D texture mipmap level is a
          ;; layer. So each image in a 3D texture is uniquely identified by a
          ;; layer and a mipmap level.
          ;; A single mipmap level of a 3D texture is a layered image, where the
          ;; number of layers is the depth of that particular mipmap level.
          (:texture-3d (%gl:framebuffer-texture-layer target attachment tex-id
                                                      mipmap-level layer-num))
          ;; Each mipmap level of a 1D Array Textures contains a number of images,
          ;; equal to the count images in the array. While these images are
          ;; technically one-dimensional, they are promoted to 2D status for FBO
          ;; purposes in the same way as a non-array 1D texture: by using a height
          ;; of 1. Thus, each individual image is uniquely identified by a layer
          ;; (the array index) and a mipmap level.
          ;; A single mipmap level of a 1D Array Texture is a layered image, where
          ;; the number of layers is the array size.
          (:texture-1d-array (%gl:framebuffer-texture-layer
                              target attachment tex-id mipmap-level layer-num))
          ;; 2D Array textures are much like 3D textures, except instead of the
          ;; number of Z slices, it is the array count. Each 2D image in an array
          ;; texture can be uniquely identified by a layer (the array index) and a
          ;; mipmap level. Unlike 3D textures, the array count doesn't change when
          ;; going down the mipmap hierarchy.
          ;; A single mipmap level of a 2D Array Texture is a layered image, where
          ;; the number of layers is the array size.
          (:texture-2d-array (%gl:framebuffer-texture-layer
                              target attachment tex-id mipmap-level layer-num))
          ;; A Rectangle Texture has a single 2D image, and thus is identified by
          ;; mipmap level 0.
          (:texture-rectangle (gl:framebuffer-texture-2d target attachment :texture-2d
                                                         tex-id 0))
          ;; When attaching a cubemap, you must use the Texture2D function, and
          ;; the textarget must be one of the 6 targets for cubemap binding.
          ;; Cubemaps contain 6 targets, each of which is a 2D image. Thus, each
          ;; image in a cubemap texture can be uniquely identified by a target
          ;; and a mipmap level.
          ;; Also, a mipmap level of a Cubemap Texture is a layered image. For
          ;; cubemaps, you get exactly 6 layers, one for each face. And the order
          ;; of the faces is the same as the order of the enumerators:
          ;; Layer number 	Cubemap face
          ;; 0 	GL_TEXTURE_CUBE_MAP_POSITIVE_X
          ;; 1 	GL_TEXTURE_CUBE_MAP_NEGATIVE_X
          ;; 2 	GL_TEXTURE_CUBE_MAP_POSITIVE_Y
          ;; 3 	GL_TEXTURE_CUBE_MAP_NEGATIVE_Y
          ;; 4 	GL_TEXTURE_CUBE_MAP_POSITIVE_Z
          ;; 5 	GL_TEXTURE_CUBE_MAP_NEGATIVE_Z
          (:texture-cube-map (gl:framebuffer-texture-2d
                              target attachment '&&&CUBEMAP-TARGET&&&
                              tex-id mipmap-level))
          ;; Buffer Textures work like 1D texture, only they have a single image,
          ;; identified by mipmap level 0.
          (:texture-buffer ())
          ;; Cubemap array textures work like 2D array textures, only with 6 times
          ;; the number of images. Thus a 2D image in the array is identified by
          ;; the array layer (technically layer-face) and a mipmap level.
          ;; For cubemap arrays, the value that gl_Layer represents is the
          ;; layer-face index. Thus it is the face within a layer, ordered as
          ;; above. So if you want to render to the 3rd layer, +z face, you would
          ;; set gl_Layer to (2 * 6) + 4, or 16.
          (:texture-cube-map-array ()))))))

(defun attachment-compatible (attachment internal-format)
  (case attachment
    (:depth-attachment (depth-formatp internal-format))
    (:stencil-attachment (stencil-formatp internal-format))
    (:depth-stencil-attachment (depth-stencil-formatp internal-format))
    (otherwise (color-renderable-formatp internal-format))))

(defun fbo-detach (attachment)
  ;; The texture argument is the texture object name you want to attach from.
  ;; If you pass zero as texture, this has the effect of clearing the attachment
  ;; for this attachment, regardless of what kind of image was attached there.
  (%gl:framebuffer-texture-layer :draw-framebuffer attachment 0 0 0))
