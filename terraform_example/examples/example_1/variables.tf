variable "volumev3" {
  description = "API Access volumev3"
  type        = string
}

#= {
#        root = {
#            type            = "ceph-ssd"
#            size            = 10
#        }
#    }

variable "volumes"{
  description = "List of Volumes to attach to Instance. Boot drive should always have 'root' name"
  type = map (object({
    type = string
    size = number
  }))
}